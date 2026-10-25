import Foundation

/// 오디오 녹음기. 테스트에서는 가짜 구현을 쓴다.
@MainActor
public protocol AudioRecording: AnyObject {
    var isRecording: Bool { get }
    /// 일시정지 중인지. 일시정지 중에도 `isRecording`은 true다.
    var isPaused: Bool { get }
    /// 녹음된 길이(초).
    var currentTime: TimeInterval { get }
    /// `url`에 새 파일로 녹음을 시작한다.
    func start(to url: URL) throws
    /// 녹음을 잠시 멈춘다. 같은 파일에 이어서 쓰며, 멈춘 동안 `currentTime`은 늘지 않는다.
    func pause()
    /// 일시정지한 녹음을 같은 파일에 이어서 녹음한다.
    func resume() throws
    /// 녹음을 멈추고 파일을 닫는다. 녹음된 길이(초)를 돌려준다.
    func stop() -> TimeInterval
}

#if canImport(AVFoundation)
import AVFoundation

/// `AVAudioRecorder`로 CAF(PCM) 파일을 녹음한다. 모노 16kHz 16비트라 3시간에 약 346MB이고,
/// 압축하지 않은 파일은 강제 종료돼도 그때까지 재생된다. 정지 뒤 `SystemAudioConverter`가 m4a로 압축한다.
@MainActor
public final class SystemAudioRecorder: NSObject, AudioRecording {
    public enum RecorderError: Error, LocalizedError {
        case couldNotStart
        case couldNotResume

        public var errorDescription: String? {
            switch self {
            case .couldNotStart: "녹음을 시작하지 못했습니다."
            case .couldNotResume: "녹음을 다시 시작하지 못했습니다."
            }
        }
    }

    public static let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 16_000,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
    ]

    private var recorder: AVAudioRecorder?
    private var paused = false

    public override init() {}

    public var isRecording: Bool { recorder != nil }
    public var isPaused: Bool { paused }
    public var currentTime: TimeInterval { recorder?.currentTime ?? 0 }

    public func start(to url: URL) throws {
        let recorder = try AVAudioRecorder(url: url, settings: Self.settings)
        recorder.delegate = self
        guard recorder.prepareToRecord(), recorder.record() else {
            Log.recording.error("녹음 시작 실패: \(url.lastPathComponent, privacy: .public)")
            throw RecorderError.couldNotStart
        }
        self.recorder = recorder
        paused = false
        Log.recording.info("녹음 시작: \(url.lastPathComponent, privacy: .public)")
    }

    public func pause() {
        guard let recorder, !paused else { return }
        recorder.pause()
        paused = true
        Log.recording.info("녹음 일시정지")
    }

    public func resume() throws {
        guard let recorder, paused else { return }
        guard recorder.record() else {
            Log.recording.error("녹음 재개 실패")
            throw RecorderError.couldNotResume
        }
        paused = false
        Log.recording.info("녹음 재개")
    }

    public func stop() -> TimeInterval {
        guard let recorder else { return 0 }
        let duration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        paused = false
        Log.recording.info("녹음 정지: \(duration, privacy: .public)초")
        return duration
    }
}

extension SystemAudioRecorder: AVAudioRecorderDelegate {
    nonisolated public func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Log.recording.error("녹음 인코딩 오류: \(error?.localizedDescription ?? "알 수 없음", privacy: .public)")
    }

    nonisolated public func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            Log.recording.error("녹음이 정상적으로 끝나지 않음")
        }
    }
}
#endif
