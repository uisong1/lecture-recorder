#if canImport(SwiftData)
import Foundation
import Observation

/// 고를 수 있는 재생 속도.
public enum PlaybackRate: Float, CaseIterable, Sendable {
    case x075 = 0.75
    case normal = 1.0
    case x125 = 1.25
    case x150 = 1.5
    case x200 = 2.0
    case x250 = 2.5
    case x300 = 3.0

    public var label: String {
        switch self {
        case .x075: "0.75배"
        case .normal: "1.0배"
        case .x125: "1.25배"
        case .x150: "1.5배"
        case .x200: "2.0배"
        case .x250: "2.5배"
        case .x300: "3.0배"
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
    /// 지금 재생 속도. 과목마다 마지막에 고른 속도를 기억하고, 정한 적 없는 과목(과 미분류)은 마지막으로 고른 속도를 쓴다. 앱을 다시 켜도 유지한다.
    public private(set) var rate: PlaybackRate

    /// 이 간격(초) 안에 이미 북마크가 있으면 같은 자리로 보고 새로 만들지 않는다.
    public static let duplicateBookmarkWindow: TimeInterval = 1

    /// 앞뒤 건너뛰기 간격(초).
    public static let skipInterval: TimeInterval = 15

    /// 끝에서 이 시간(초) 안쪽까지 들었으면 다 들은 것으로 보고 다음엔 처음부터 듣는다.
    public static let finishedMargin: TimeInterval = 3

    /// 켜면 한 녹음이 끝났을 때 목록의 다음 녹음을 이어서 튼다. 선택은 기억한다.
    public var continuousPlayback: Bool {
        didSet { defaults.set(continuousPlayback, forKey: Self.continuousPlaybackKey) }
    }

    /// 북마크 이어 듣기의 구간들. 이어 듣는 중이 아니면 비어 있다.
    public private(set) var tourStops: [BookmarkTourStop] = []
    /// 지금 듣는 구간의 순번 (`tourStops` 안).
    public private(set) var tourIndex = 0
    /// 북마크만 이어 듣는 중인지.
    public var isTouring: Bool { !tourStops.isEmpty }
    /// "3/12 북마크 구간". 이어 듣는 중이 아니면 nil.
    public var tourPositionText: String? {
        isTouring ? "\(tourIndex + 1)/\(tourStops.count) 북마크 구간" : nil
    }
    private var isSteppingTour = false

    static let continuousPlaybackKey = "continuousPlayback"
    static let rateKey = "playbackRate"

    private let player: any AudioPlaying
    private let storage: RecordingStorage
    private let bookmarkManager: BookmarkManager?
    private let now: @MainActor () -> Date
    private let savePosition: @MainActor () -> Void
    private let defaults: UserDefaults
    private let queue: @MainActor () -> [Recording]
    private let isPlayable: @MainActor (Recording) -> Bool
    private let allowsAdvance: @MainActor () -> Bool

    /// - Parameters:
    ///   - queue: 지금 화면에 보이는 목록(정렬·필터 반영). 이어서 재생할 때 다음 녹음을 여기서 고른다.
    ///   - isPlayable: 파일이 있어 재생할 수 있는 녹음인지. 아니면 건너뛴다.
    ///   - allowsAdvance: false면 이어서 재생하지 않는다 (예: 녹음 중).
    public init(
        player: any AudioPlaying,
        storage: RecordingStorage,
        bookmarkManager: BookmarkManager? = nil,
        now: @escaping @MainActor () -> Date = { Date() },
        savePosition: @escaping @MainActor () -> Void = {},
        defaults: UserDefaults = .standard,
        queue: @escaping @MainActor () -> [Recording] = { [] },
        isPlayable: @escaping @MainActor (Recording) -> Bool = { _ in true },
        allowsAdvance: @escaping @MainActor () -> Bool = { true }
    ) {
        self.player = player
        self.storage = storage
        self.bookmarkManager = bookmarkManager
        self.now = now
        self.savePosition = savePosition
        self.defaults = defaults
        self.queue = queue
        self.isPlayable = isPlayable
        self.allowsAdvance = allowsAdvance
        continuousPlayback = defaults.bool(forKey: Self.continuousPlaybackKey)
        // 저장된 값이 없거나(0) 알 수 없는 값이면 보통 속도로 시작한다.
        let global = PlaybackRate(rawValue: defaults.float(forKey: Self.rateKey)) ?? .normal
        globalRate = global
        rate = global
    }

    /// 과목에 기억해 둔 속도가 없을 때 쓰는, 마지막으로 고른 속도.
    private var globalRate: PlaybackRate

    /// 목록에서 `current` 다음으로 틀 녹음. 재생할 수 없는 녹음은 건너뛴다.
    /// `current`가 목록에 없거나(검색 조건이 바뀌어 빠진 경우 등) 마지막이면 nil이다.
    public static func nextRecording(after current: Recording, in list: [Recording], isPlayable: (Recording) -> Bool) -> Recording? {
        guard let index = list.firstIndex(where: { $0 === current }) else { return nil }
        return list[(index + 1)...].first(where: isPlayable)
    }

    public var currentTime: TimeInterval { player.currentTime }
    public var duration: TimeInterval { player.duration }

    /// 녹음을 불러온다. 같은 녹음이면 다시 불러오지 않는다.
    public func select(_ recording: Recording?) {
        if !isSteppingTour { endTour() }
        guard recording !== current else { return }
        rememberPosition()
        player.stop()
        isPlaying = false
        current = nil
        guard let recording else { return }
        do {
            rate = recording.subject?.playbackRate ?? globalRate
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
        guard let current else { return }
        player.play()
        isPlaying = player.isPlaying
        if isPlaying { markPlayed(current) }
    }

    /// 재생을 시작한 시각을 녹음에 적는다. 처음 듣는 것이면 목록의 "안 들음" 표시가 바로 사라지도록 곧장 저장하고,
    /// 이미 들은 녹음의 시각 갱신은 다음 저장 때 함께 저장한다.
    private func markPlayed(_ recording: Recording) {
        let wasUnplayed = recording.lastPlayedAt == nil
        recording.lastPlayedAt = now()
        if wasUnplayed { savePosition() }
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

    /// 지금 위치에서 `seconds`초만큼 건너뛴다 (음수면 뒤로). 0~길이 밖으로는 나가지 않는다.
    public func skip(by seconds: TimeInterval) {
        seek(to: player.currentTime + seconds)
    }

    public func skipForward() { skip(by: Self.skipInterval) }
    public func skipBackward() { skip(by: -Self.skipInterval) }

    /// 속도를 바꾼다. 지금 녹음의 과목에 기억해 두고, 과목이 없는 녹음이나 기억이 없는 과목을 위해 전체 기본으로도 남긴다.
    public func setRate(_ newRate: PlaybackRate) {
        rate = newRate
        globalRate = newRate
        player.rate = newRate.rawValue
        defaults.set(newRate.rawValue, forKey: Self.rateKey)
        if let subject = current?.subject, subject.playbackRate != newRate {
            subject.playbackRate = newRate
            savePosition()
        }
    }

    /// 불러온 녹음의 북마크. 시점 순서.
    public var bookmarks: [Bookmark] { current?.sortedBookmarks ?? [] }

    /// 슬라이더 위에 표시할 북마크 위치(0~1). 길이를 모르면 비어 있다.
    public var bookmarkMarkers: [Double] {
        guard duration > 0 else { return [] }
        return bookmarks.map { min(max($0.time / duration, 0), 1) }
    }

    /// 북마크로 이동할 때 시점보다 이만큼(초) 앞에서 튼다. 북마크는 소리를 들은 뒤에 누르므로 정확한 시점부터 틀면 중요한 말이 이미 지나가 있다.
    public static let bookmarkLeadIn: TimeInterval = 5

    /// 북마크 시점에서 `bookmarkLeadIn`초 앞. 0 밑으로 내려가지 않고 길이를 넘지 않는다. 저장된 시점은 바꾸지 않는다.
    public static func playbackStart(forBookmarkAt time: TimeInterval, duration: TimeInterval) -> TimeInterval {
        min(max(time - bookmarkLeadIn, 0), max(duration, 0))
    }

    /// 북마크 시점 `bookmarkLeadIn`초 앞으로 이동해 그곳부터 재생한다.
    public func play(from bookmark: Bookmark) {
        guard current != nil else { return }
        endTour()
        seek(to: Self.playbackStart(forBookmarkAt: bookmark.time, duration: duration))
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

    /// 목록의 북마크를 날짜순으로 차례로 듣는다. 각 북마크는 `bookmarkLeadIn`초 앞에서 `BookmarkTour.segmentLength`초 재생한다.
    /// 파일이 없는 녹음은 건너뛴다. 들을 구간이 없으면 안내만 남긴다.
    public func startBookmarkTour(entries: [BookmarkEntry]) {
        let stops = BookmarkTour.stops(for: entries, isPlayable: isPlayable)
        guard !stops.isEmpty else {
            errorMessage = "이어 들을 북마크가 없습니다."
            return
        }
        tourStops = stops
        tourIndex = 0
        errorMessage = nil
        playTourStop()
    }

    /// 이어 듣기를 끝낸다. 재생 중이던 소리는 그대로 두지 않고 멈춘다.
    public func stopBookmarkTour() {
        guard isTouring else { return }
        endTour()
        pause()
    }

    /// 다음 구간으로. 마지막이면 이어 듣기를 끝내고 멈춘다.
    public func nextTourStop() {
        guard isTouring else { return }
        guard tourIndex + 1 < tourStops.count else {
            stopBookmarkTour()
            return
        }
        tourIndex += 1
        playTourStop()
    }

    /// 이전 구간으로. 첫 구간이면 그 구간 처음부터 다시 듣는다.
    public func previousTourStop() {
        guard isTouring else { return }
        tourIndex = max(tourIndex - 1, 0)
        playTourStop()
    }

    private func endTour() {
        tourStops = []
        tourIndex = 0
    }

    /// `tourIndex`의 구간을 불러와 튼다. 불러오지 못하는 녹음은 건너뛰고, 모두 못 열면 끝낸다.
    private func playTourStop() {
        while tourIndex < tourStops.count {
            let stop = tourStops[tourIndex]
            isSteppingTour = true
            select(stop.recording)
            isSteppingTour = false
            if current === stop.recording {
                seek(to: stop.start)
                play()
                return
            }
            tourIndex += 1
        }
        endTour()
    }

    /// 재생이 끝났는지 화면 갱신 때 확인한다.
    public func refresh() {
        let wasPlaying = isPlaying
        isPlaying = player.isPlaying
        if isTouring {
            // 구간 끝에 닿았거나, 녹음 끝에서 스스로 멈췄으면 다음 구간으로 넘어간다. 사용자가 멈춘 것은 `isPlaying`이 먼저 꺼져 여기 오지 않는다.
            let stop = tourStops[tourIndex]
            if isPlaying && player.currentTime >= stop.end || wasPlaying && !isPlaying {
                nextTourStop()
            }
            return
        }
        guard wasPlaying && !isPlaying else { return }
        let finished = hasReachedEnd
        rememberPosition()
        // 사용자가 멈추거나 다른 녹음을 고르면 `isPlaying`이 먼저 꺼지므로 여기에 오지 않는다. 끝까지 재생된 경우만 이어 튼다.
        if finished { advanceToNextRecording() }
    }

    /// 재생이 스스로 멈췄을 때 끝까지 들은 것인지 (끝 가까이거나 처음 위치로 돌아감).
    private var hasReachedEnd: Bool {
        let time = player.currentTime
        return time <= 0 || time >= player.duration - Self.finishedMargin
    }

    /// 이어서 재생이 켜져 있으면 목록의 다음 녹음을 불러와 튼다. 마지막이거나 녹음 중이면 멈춘 채 둔다.
    private func advanceToNextRecording() {
        guard continuousPlayback, allowsAdvance(), let current,
              let next = Self.nextRecording(after: current, in: queue(), isPlayable: isPlayable) else { return }
        select(next)
        play()
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
