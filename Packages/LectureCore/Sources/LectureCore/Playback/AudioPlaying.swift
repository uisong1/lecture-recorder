import Foundation

/// 오디오 재생기. 테스트에서는 가짜 구현을 쓴다.
@MainActor
public protocol AudioPlaying: AnyObject {
    var isPlaying: Bool { get }
    /// 재생 위치(초).
    var currentTime: TimeInterval { get }
    /// 전체 길이(초). 불러온 파일이 없으면 0.
    var duration: TimeInterval { get }
    /// 파일을 불러온다. 재생은 시작하지 않는다.
    /// 재생 속도. 1.0이 보통 속도.
    var rate: Float { get set }
    func load(_ url: URL) throws
    /// 재생 위치를 옮긴다. 범위를 넘으면 0~길이로 맞춘다.
    func seek(to time: TimeInterval)
    func play()
    func pause()
    func stop()
}

#if canImport(AVFoundation)
import AVFoundation

/// `AVAudioPlayer`로 재생한다.
@MainActor
public final class SystemAudioPlayer: NSObject, AudioPlaying {
    public enum PlayerError: Error, LocalizedError {
        case couldNotPlay

        public var errorDescription: String? { "녹음 파일을 재생할 수 없습니다." }
    }

    private var player: AVAudioPlayer?

    public override init() {}

    public var isPlaying: Bool { player?.isPlaying ?? false }
    public var currentTime: TimeInterval { player?.currentTime ?? 0 }
    public var duration: TimeInterval { player?.duration ?? 0 }

    public var rate: Float = 1 {
        didSet { player?.rate = rate }
    }

    public func seek(to time: TimeInterval) {
        player?.currentTime = min(max(time, 0), duration)
    }

    public func load(_ url: URL) throws {
        player?.stop()
        let player = try AVAudioPlayer(contentsOf: url)
        player.enableRate = true
        guard player.prepareToPlay() else {
            Log.playback.error("재생 준비 실패: \(url.lastPathComponent, privacy: .public)")
            throw PlayerError.couldNotPlay
        }
        player.rate = rate
        self.player = player
    }

    public func play() {
        guard let player, player.play() else {
            Log.playback.error("재생 시작 실패")
            return
        }
    }

    public func pause() { player?.pause() }

    public func stop() {
        player?.stop()
        player?.currentTime = 0
    }
}
#endif
