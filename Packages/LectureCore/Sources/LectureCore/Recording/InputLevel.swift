import Foundation

/// 마이크 입력 크기. 데시벨(-160...0)을 화면에 그리기 좋은 0...1로 바꾼다.
public enum InputLevel {
    /// 이보다 작은 소리는 0으로 본다.
    public static let floorDecibels: Float = -60
    /// 이보다 작으면 "거의 무음"이다 (-50dB, 조용한 방의 숨소리 수준).
    public static let silenceThreshold: Float = normalize(decibels: -50)

    /// -60dB 이하는 0, 0dB는 1. 숫자가 아닌 값은 0.
    public static func normalize(decibels: Float) -> Float {
        guard decibels.isFinite else { return decibels == .infinity ? 1 : 0 }
        return min(max((decibels - floorDecibels) / -floorDecibels, 0), 1)
    }
}

/// 입력이 오래 무음인지 판정한다 (교수님과 멀거나 마이크가 막혔을 때 알려 주기 위해).
/// 시각을 직접 받으므로 가짜 시계로 테스트할 수 있다.
public struct SilenceDetector: Sendable {
    /// 이 시간(초)을 넘게 계속 무음이면 경고한다.
    public static let warningAfter: TimeInterval = 10

    private var silentSince: Date?

    public init() {}

    /// 새 입력 크기를 알리고, 지금 경고해야 하는지 돌려준다. 소리가 한 번이라도 들어오면 처음부터 다시 센다.
    public mutating func update(level: Float, at now: Date) -> Bool {
        guard level < InputLevel.silenceThreshold else {
            silentSince = nil
            return false
        }
        let start = silentSince ?? now
        silentSince = start
        return now.timeIntervalSince(start) > Self.warningAfter
    }

    public mutating func reset() {
        silentSince = nil
    }
}

/// 녹음을 시작하기 전에 마이크 소리 크기만 미리 듣는 곳. 파일에는 아무것도 쓰지 않는다.
/// 테스트에서는 가짜 구현을 쓴다.
@MainActor
public protocol AudioLevelPreviewing: AnyObject {
    /// 지금 입력 크기 (0...1, `InputLevel` 참고). 켜져 있지 않으면 0.
    var level: Float { get }
    func start() throws
    func stop()
}

#if canImport(AVFoundation) && os(macOS)
import AVFoundation
import os

/// `AVAudioEngine`의 입력 탭으로 소리 크기를 읽는다. 마이크 권한이 있을 때만 켜야 한다.
@MainActor
public final class SystemAudioLevelPreview: AudioLevelPreviewing {
    private let engine = AVAudioEngine()
    private let latest = OSAllocatedUnfairLock<Float>(initialState: 0)
    private var isRunning = false

    public init() {}

    public var level: Float { isRunning ? latest.withLock { $0 } : 0 }

    public func start() throws {
        guard !isRunning else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { throw PreviewError.noInput }
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.tapBlock(storing: latest))
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        isRunning = true
    }

    public func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        latest.withLock { $0 = 0 }
    }

    /// 오디오 스레드에서 불리는 탭. 메인 액터 밖에서 만들어야 격리 검사에 걸리지 않는다.
    nonisolated private static func tapBlock(storing latest: OSAllocatedUnfairLock<Float>) -> AVAudioNodeTapBlock {
        { buffer, _ in
            guard let samples = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            guard count > 0 else { return }
            var sum: Float = 0
            for index in 0..<count { sum += samples[index] * samples[index] }
            let rms = (sum / Float(count)).squareRoot()
            let decibels = rms > 0 ? 20 * log10(rms) : -160
            latest.withLock { $0 = InputLevel.normalize(decibels: decibels) }
        }
    }

    enum PreviewError: Error { case noInput }
}
#endif
