import Foundation

/// 녹음 파일(CAF)을 압축된 m4a로 바꾼다. 테스트에서는 가짜 구현을 쓴다.
public protocol AudioConverting: Sendable {
    /// `source`를 읽어 `destination`에 AAC m4a로 쓰고, 변환된 길이(초)를 돌려준다.
    func compress(from source: URL, to destination: URL) async throws -> TimeInterval
}

/// 압축본이 원본 길이를 제대로 담았는지 가린다. 압축본이 확인되기 전에는 CAF를 지우지 않는다.
public enum ConversionCheck {
    /// AAC가 앞뒤에 붙이는 여유와 반올림을 허용하는 오차 (초).
    public static let toleranceSeconds: TimeInterval = 1
    /// 길이에 비례해 허용하는 오차 비율.
    public static let toleranceRatio = 0.005

    public static func isComplete(sourceSeconds: TimeInterval, convertedSeconds: TimeInterval) -> Bool {
        guard sourceSeconds > 0 else { return true }
        return convertedSeconds >= sourceSeconds - max(toleranceSeconds, sourceSeconds * toleranceRatio)
    }
}

#if canImport(AVFoundation)
import AVFoundation

/// `AVAudioFile`로 읽고 써서 AAC(16kHz 모노 32kbps)로 압축한다. 작은 소리는 `VolumeNormalizer` 배율로 키운다. 90분에 약 22MB, 3시간에 약 43MB.
public struct SystemAudioConverter: AudioConverting {
    /// 입력과 같은 샘플레이트로 쓴다. 다르게 쓰면 길이가 어긋난다. 16kHz 모노는 64kbps를 받지 않아 32kbps로 한다.
    public static func outputSettings(sampleRate: Double) -> [String: Any] { [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: RecordingFormat.compressedBitRate,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
    ] }

    /// 한 번에 읽는 프레임 수. 3시간짜리도 메모리를 조금만 쓰게 나눠서 처리한다.
    private static let chunkFrames: AVAudioFrameCount = 64 * 1024

    public init() {}

    public func compress(from source: URL, to destination: URL) async throws -> TimeInterval {
        // 오래 걸리는 변환이 메인 스레드를 막지 않게 한다.
        try await Task.detached(priority: .utility) {
            try Self.convert(from: source, to: destination)
        }.value
    }

    /// 처음부터 끝까지 읽어 가장 큰 소리 크기(0...1)를 찾는다. 한 번에 한 조각만 읽는다.
    private static func peakLevel(of file: AVAudioFile, buffer: AVAudioPCMBuffer) throws -> Float {
        // 읽다가 실패해도 본 변환이 처음부터 시작하도록 항상 되감는다. 그러지 않으면 뒷부분만 압축하고 CAF를 지운다.
        defer { file.framePosition = 0 }
        file.framePosition = 0
        var peak: Float = 0
        while file.framePosition < file.length {
            try file.read(into: buffer, frameCount: chunkFrames)
            guard buffer.frameLength > 0 else { break }
            guard let channels = buffer.floatChannelData else { return 0 }
            for channel in 0..<Int(buffer.format.channelCount) {
                for frame in 0..<Int(buffer.frameLength) {
                    peak = max(peak, abs(channels[channel][frame]))
                }
            }
        }
        return peak
    }

    private static func apply(gain: Float, to buffer: AVAudioPCMBuffer) {
        guard gain != 1, let channels = buffer.floatChannelData else { return }
        for channel in 0..<Int(buffer.format.channelCount) {
            for frame in 0..<Int(buffer.frameLength) {
                channels[channel][frame] *= gain
            }
        }
    }

    private static func convert(from source: URL, to destination: URL) throws -> TimeInterval {
        let input = try AVAudioFile(forReading: source)
        let format = input.processingFormat
        // 변환이 끝나 변수 범위를 벗어나야 파일이 닫히고 m4a 끝부분이 쓰인다.
        var output: AVAudioFile? = try AVAudioFile(
            forWriting: destination,
            settings: Self.outputSettings(sampleRate: format.sampleRate),
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
            throw CocoaError(.fileWriteUnknown)
        }
        // 작은 소리를 키우는 배율. 읽기에 실패해도 원본 음량으로 압축한다.
        let gain = (try? peakLevel(of: input, buffer: buffer)).map(VolumeNormalizer.gain(forPeak:)) ?? 1
        if gain != 1 { Log.recording.info("음량 자동 정규화 배율 \(gain, privacy: .public)") }
        while input.framePosition < input.length {
            try input.read(into: buffer, frameCount: chunkFrames)
            guard buffer.frameLength > 0 else { break }
            apply(gain: gain, to: buffer)
            try output?.write(from: buffer)
        }
        output = nil
        // 압축본이 원본보다 눈에 띄게 짧으면 실패로 본다. 그래야 CAF가 지워지지 않는다.
        let sourceSeconds = Double(input.length) / format.sampleRate
        let written = try AVAudioFile(forReading: destination)
        let writtenSeconds = Double(written.length) / written.processingFormat.sampleRate
        guard ConversionCheck.isComplete(sourceSeconds: sourceSeconds, convertedSeconds: writtenSeconds) else {
            Log.recording.error("압축본이 짧음: 원본 \(sourceSeconds, privacy: .public)초, 압축본 \(writtenSeconds, privacy: .public)초")
            throw CocoaError(.fileWriteUnknown)
        }
        return sourceSeconds
    }
}
#endif
