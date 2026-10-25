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

    private let player: any AudioPlaying
    private let storage: RecordingStorage

    public init(player: any AudioPlaying, storage: RecordingStorage) {
        self.player = player
        self.storage = storage
    }

    public var currentTime: TimeInterval { player.currentTime }
    public var duration: TimeInterval { player.duration }

    /// 녹음을 불러온다. 같은 녹음이면 다시 불러오지 않는다.
    public func select(_ recording: Recording?) {
        guard recording !== current else { return }
        player.stop()
        isPlaying = false
        current = nil
        guard let recording else { return }
        do {
            player.rate = rate.rawValue
            try player.load(storage.url(for: recording.relativePath))
            current = recording
            errorMessage = nil
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

    /// 재생이 끝났는지 화면 갱신 때 확인한다.
    public func refresh() {
        isPlaying = player.isPlaying
    }
}
#endif
