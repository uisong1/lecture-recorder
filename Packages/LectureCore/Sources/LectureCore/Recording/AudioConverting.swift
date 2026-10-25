import Foundation

/// 녹음 파일(CAF)을 압축된 m4a로 바꾼다. 테스트에서는 가짜 구현을 쓴다.
public protocol AudioConverting: Sendable {
    /// `source`를 읽어 `destination`에 AAC m4a로 쓰고, 변환된 길이(초)를 돌려준다.
    func compress(from source: URL, to destination: URL) async throws -> TimeInterval
}

#if canImport(AVFoundation)
import AVFoundation

/// `AVAudioFile`로 읽고 써서 AAC(모노 64kbps)로 압축한다. 90분에 약 43MB, 3시간에 약 86MB.
public struct SystemAudioConverter: AudioConverting {
    public static let outputSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 44_100,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 64_000,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
    ]

    /// 한 번에 읽는 프레임 수. 3시간짜리도 메모리를 조금만 쓰게 나눠서 처리한다.
    private static let chunkFrames: AVAudioFrameCount = 64 * 1024

    public init() {}

    public func compress(from source: URL, to destination: URL) async throws -> TimeInterval {
        // 오래 걸리는 변환이 메인 스레드를 막지 않게 한다.
        try await Task.detached(priority: .utility) {
            try Self.convert(from: source, to: destination)
        }.value
    }

    private static func convert(from source: URL, to destination: URL) throws -> TimeInterval {
        let input = try AVAudioFile(forReading: source)
        let format = input.processingFormat
        // 변환이 끝나 변수 범위를 벗어나야 파일이 닫히고 m4a 끝부분이 쓰인다.
        var output: AVAudioFile? = try AVAudioFile(
            forWriting: destination,
            settings: Self.outputSettings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
            throw CocoaError(.fileWriteUnknown)
        }
        while input.framePosition < input.length {
            try input.read(into: buffer, frameCount: chunkFrames)
            guard buffer.frameLength > 0 else { break }
            try output?.write(from: buffer)
        }
        output = nil
        return Double(input.length) / format.sampleRate
    }
}
#endif
