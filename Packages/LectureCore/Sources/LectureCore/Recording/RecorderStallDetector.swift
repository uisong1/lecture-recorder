import Foundation

/// 녹음기가 조용히 멈췄는지 판정한다. 녹음 중 일정 간격(10초)으로 `update`를 부른다.
/// 시계나 녹음기를 직접 읽지 않는 순수한 값이라 테스트하기 쉽다.
public struct RecorderStallDetector: Equatable {
    /// 점검 간격. 컨트롤러의 주기 점검과 같다.
    public static let checkInterval: TimeInterval = 10
    /// 경과 시간이 이만큼 연속으로 늘지 않으면 멈춘 것으로 본다 (3번 × 10초 = 30초).
    public static let stalledChecks = 3

    public enum Verdict: Equatable {
        case healthy
        case stalled(Reason)
    }

    public enum Reason: Equatable {
        /// 녹음기가 끝났다고 알렸거나 더 이상 녹음하지 않는다.
        case recorderEnded
        /// 경과 시간이 `stalledChecks`번 연속으로 늘지 않았다.
        case noProgress
    }

    private var lastElapsed: TimeInterval?
    public private(set) var stagnantChecks = 0

    public init() {}

    public mutating func reset() {
        lastElapsed = nil
        stagnantChecks = 0
    }

    /// - Parameters:
    ///   - elapsed: 녹음기가 센 경과 시간(초).
    ///   - isPaused: 일시정지 중이면 시간이 서지 않는 게 정상이므로 경고하지 않고 세던 횟수도 지운다.
    ///   - recorderEnded: 녹음기가 스스로 끝났다고 알린 경우. 바로 멈춘 것으로 본다.
    public mutating func update(elapsed: TimeInterval, isPaused: Bool, recorderEnded: Bool) -> Verdict {
        if isPaused {
            reset()
            lastElapsed = elapsed
            return .healthy
        }
        if recorderEnded { return .stalled(.recorderEnded) }
        defer { lastElapsed = elapsed }
        // 첫 점검은 기준만 잡는다.
        guard let last = lastElapsed else { return .healthy }
        if elapsed > last {
            stagnantChecks = 0
            return .healthy
        }
        stagnantChecks += 1
        return stagnantChecks >= Self.stalledChecks ? .stalled(.noProgress) : .healthy
    }
}
