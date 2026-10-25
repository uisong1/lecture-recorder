import Foundation

/// 오디오 파일의 길이를 읽는다. 테스트에서는 가짜 구현을 쓴다.
public protocol AudioDurationReading: Sendable {
    /// 길이(초). 파일을 열 수 없으면 nil.
    func duration(of url: URL) async -> TimeInterval?
}

#if canImport(AVFoundation)
import AVFoundation

/// `AVAudioFile`로 열어 길이를 잰다.
public struct SystemAudioDurationReader: AudioDurationReading {
    public init() {}

    public func duration(of url: URL) async -> TimeInterval? {
        await Task.detached(priority: .utility) { () -> TimeInterval? in
            guard let file = try? AVAudioFile(forReading: url) else { return nil }
            let rate = file.processingFormat.sampleRate
            guard rate > 0, file.length > 0 else { return nil }
            return Double(file.length) / rate
        }.value
    }
}
#endif
