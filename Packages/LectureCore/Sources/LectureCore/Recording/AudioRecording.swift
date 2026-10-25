import Foundation

/// 오디오 녹음기. 테스트에서는 가짜 구현을 쓴다.
@MainActor
public protocol AudioRecording: AnyObject {
    var isRecording: Bool { get }
    /// 녹음된 길이(초).
    var currentTime: TimeInterval { get }
    /// `url`에 새 파일로 녹음을 시작한다.
    func start(to url: URL) throws
    /// 녹음을 멈추고 파일을 닫는다. 녹음된 길이(초)를 돌려준다.
    func stop() -> TimeInterval
}

#if canImport(AVFoundation)
import AVFoundation

/// `AVAudioRecorder`로 AAC(.m4a) 파일을 녹음한다. 모노 64kbps라 90분에 약 43MB.
@MainActor
public final class SystemAudioRecorder: NSObject, AudioRecording {
    public enum RecorderError: Error, LocalizedError {
        case couldNotStart

        public var errorDescription: String? { "녹음을 시작하지 못했습니다." }
    }

    public static let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 44_100,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 64_000,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
    ]

    private var recorder: AVAudioRecorder?

    public override init() {}

    public var isRecording: Bool { recorder?.isRecording ?? false }
    public var currentTime: TimeInterval { recorder?.currentTime ?? 0 }

    public func start(to url: URL) throws {
        let recorder = try AVAudioRecorder(url: url, settings: Self.settings)
        recorder.delegate = self
        guard recorder.prepareToRecord(), recorder.record() else {
            Log.recording.error("녹음 시작 실패: \(url.lastPathComponent, privacy: .public)")
            throw RecorderError.couldNotStart
        }
        self.recorder = recorder
        Log.recording.info("녹음 시작: \(url.lastPathComponent, privacy: .public)")
    }

    public func stop() -> TimeInterval {
        guard let recorder else { return 0 }
        let duration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
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
