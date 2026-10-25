/// 시간표의 한 칸(요일, 시작, 종료)을 나타내는 값 타입.
/// 시작은 포함, 종료는 포함하지 않는다 (`[start, end)`).
public struct ClassPeriod: Hashable, Sendable {
    public let weekday: Weekday
    public let start: TimeOfDay
    public let end: TimeOfDay

    public enum ValidationError: Error, Equatable {
        /// 종료가 시작과 같거나 더 빠름.
        case endNotAfterStart
    }

    public init(weekday: Weekday, start: TimeOfDay, end: TimeOfDay) throws(ValidationError) {
        guard start < end else { throw .endNotAfterStart }
        self.weekday = weekday
        self.start = start
        self.end = end
    }

    /// 같은 요일이고 시간이 조금이라도 겹치는지. 한 칸이 끝나는 시각에 다음 칸이 시작하는 것은 겹치지 않는다.
    public func overlaps(_ other: ClassPeriod) -> Bool {
        weekday == other.weekday && start < other.end && other.start < end
    }

    /// 이 칸에 해당 시각이 들어가는지.
    public func contains(weekday: Weekday, time: TimeOfDay) -> Bool {
        self.weekday == weekday && start <= time && time < end
    }
}
