#if canImport(SwiftData)
import Foundation
import Observation

/// 고를 수 있는 재생 속도.
public enum PlaybackRate: Float, CaseIterable, Sendable {
    case normal = 1.0
    case x125 = 1.25
    case x150 = 1.5
    case x200 = 2.0

    public var label: String {
        switch self {
        case .normal: "1.0배"
        case .x125: "1.25배"
        case .x150: "1.5배"
        case .x200: "2.0배"
        }
    }
}

/// 녹음 재생을 맡는 뷰모델.
@MainActor
@Observable
public final class PlaybackController {
    /// 지금 불러온 녹음.
    public private(set) var current: Recording?
    public private(set) var isPlaying = false
    public var errorMessage: String?
    /// 고른 재생 속도. 다른 녹음을 골라도 유지한다.
    public private(set) var rate: PlaybackRate = .normal

    /// 이 간격(초) 안에 이미 북마크가 있으면 같은 자리로 보고 새로 만들지 않는다.
    public static let duplicateBookmarkWindow: TimeInterval = 1

    /// 끝에서 이 시간(초) 안쪽까지 들었으면 다 들은 것으로 보고 다음엔 처음부터 듣는다.
    public static let finishedMargin: TimeInterval = 3

    private let player: any AudioPlaying
    private let storage: RecordingStorage
    private let bookmarkManager: BookmarkManager?
    private let now: @MainActor () -> Date
    private let savePosition: @MainActor () -> Void

    public init(
        player: any AudioPlaying,
        storage: RecordingStorage,
        bookmarkManager: BookmarkManager? = nil,
        now: @escaping @MainActor () -> Date = { Date() },
        savePosition: @escaping @MainActor () -> Void = {}
    ) {
        self.player = player
        self.storage = storage
        self.bookmarkManager = bookmarkManager
        self.now = now
        self.savePosition = savePosition
    }

    public var currentTime: TimeInterval { player.currentTime }
    public var duration: TimeInterval { player.duration }

    /// 녹음을 불러온다. 같은 녹음이면 다시 불러오지 않는다.
    public func select(_ recording: Recording?) {
        guard recording !== current else { return }
        rememberPosition()
        player.stop()
        isPlaying = false
        current = nil
        guard let recording else { return }
        do {
            player.rate = rate.rawValue
            try player.load(storage.url(for: recording.relativePath))
            current = recording
            errorMessage = nil
            resume(recording)
        } catch {
            Log.playback.error("녹음 불러오기 실패 \(recording.relativePath, privacy: .public): \(error.localizedDescription, privacy: .public)")
            errorMessage = "녹음 파일을 열 수 없습니다. 파일이 옮겨졌거나 지워졌을 수 있습니다."
        }
    }

    public func play() {
        guard current != nil else { return }
        player.play()
        isPlaying = player.isPlaying
    }

    public func pause() {
        player.pause()
        isPlaying = false
        rememberPosition()
    }

    public func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    /// 원하는 위치(초)로 이동한다. 0~길이 밖이면 끝으로 맞춘다.
    public func seek(to time: TimeInterval) {
        guard current != nil else { return }
        player.seek(to: min(max(time, 0), duration))
    }

    public func setRate(_ newRate: PlaybackRate) {
        rate = newRate
        player.rate = newRate.rawValue
    }

    /// 불러온 녹음의 북마크. 시점 순서.
    public var bookmarks: [Bookmark] { current?.sortedBookmarks ?? [] }

    /// 슬라이더 위에 표시할 북마크 위치(0~1). 길이를 모르면 비어 있다.
    public var bookmarkMarkers: [Double] {
        guard duration > 0 else { return [] }
        return bookmarks.map { min(max($0.time / duration, 0), 1) }
    }

    /// 북마크 시점으로 이동해 그곳부터 재생한다.
    public func play(from bookmark: Bookmark) {
        guard current != nil else { return }
        seek(to: bookmark.time)
        play()
    }

    /// 지금 재생 위치에 북마크를 추가한다. 같은 자리(1초 이내)에 이미 있으면 만들지 않는다.
    @discardableResult
    public func addBookmarkAtCurrentTime() -> Bookmark? {
        guard let current, let bookmarkManager else { return nil }
        let time = min(max(player.currentTime, 0), duration)
        if current.bookmarks.contains(where: { abs($0.time - time) < Self.duplicateBookmarkWindow }) {
            errorMessage = "이 위치에는 이미 북마크가 있습니다."
            return nil
        }
        return perform { try bookmarkManager.add(to: current, at: time, now: now()) }
    }

    /// 북마크 메모를 고친다.
    public func updateNote(of bookmark: Bookmark, to note: String) {
        guard let bookmarkManager else { return }
        perform { try bookmarkManager.updateNote(bookmark, to: note.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    /// 북마크를 지운다.
    public func delete(_ bookmark: Bookmark) {
        guard let bookmarkManager else { return }
        current?.bookmarks.removeAll { $0 === bookmark }
        perform { try bookmarkManager.delete(bookmark) }
    }

    /// 북마크 작업을 실행하고 실패하면 오류 문구를 남긴다.
    @discardableResult
    private func perform<T>(_ action: () throws -> T) -> T? {
        do {
            let result = try action()
            errorMessage = nil
            return result
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    /// 재생이 끝났는지 화면 갱신 때 확인한다.
    public func refresh() {
        let wasPlaying = isPlaying
        isPlaying = player.isPlaying
        if wasPlaying && !isPlaying { rememberPosition() }
    }

    /// 저장해 둔 위치가 있으면 거기로 옮겨 둔다.
    private func resume(_ recording: Recording) {
        let position = recording.lastPlayedPosition
        guard position > 0, position < player.duration - Self.finishedMargin else { return }
        player.seek(to: position)
    }

    /// 지금 위치를 녹음에 적어 둔다. 처음이거나 끝에 가까우면 0으로 둔다.
    private func rememberPosition() {
        guard let current else { return }
        let time = player.currentTime
        let position = time <= 0 || time >= player.duration - Self.finishedMargin ? 0 : time
        guard current.lastPlayedPosition != position else { return }
        current.lastPlayedPosition = position
        savePosition()
    }
}
#endif
