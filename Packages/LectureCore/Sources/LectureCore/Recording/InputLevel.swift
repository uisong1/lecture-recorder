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
