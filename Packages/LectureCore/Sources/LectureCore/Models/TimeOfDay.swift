import Foundation

/// 하루 안의 시각(시:분). 시간표 칸의 시작·종료에 쓴다.
public struct TimeOfDay: Hashable, Comparable, Sendable, CustomStringConvertible {
    /// 자정부터 지난 분 (0..<1440).
    public let minutesSinceMidnight: Int

    public enum ValidationError: Error, Equatable {
        case outOfRange(hour: Int, minute: Int)
    }

    public init(hour: Int, minute: Int = 0) throws(ValidationError) {
        guard (0..<24).contains(hour), (0..<60).contains(minute) else {
            throw .outOfRange(hour: hour, minute: minute)
        }
        minutesSinceMidnight = hour * 60 + minute
    }

    /// 저장된 분 값에서 복원한다. 범위를 벗어나면 nil.
    public init?(minutesSinceMidnight: Int) {
        guard (0..<(24 * 60)).contains(minutesSinceMidnight) else { return nil }
        self.minutesSinceMidnight = minutesSinceMidnight
    }

    /// 00:00.
    public static let midnight = TimeOfDay(uncheckedMinutes: 0)

    private init(uncheckedMinutes: Int) {
        minutesSinceMidnight = uncheckedMinutes
    }

    public var hour: Int { minutesSinceMidnight / 60 }
    public var minute: Int { minutesSinceMidnight % 60 }

    public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }

    /// "09:05" 형식.
    public var description: String {
        let h = hour < 10 ? "0\(hour)" : "\(hour)"
        let m = minute < 10 ? "0\(minute)" : "\(minute)"
        return "\(h):\(m)"
    }
}

extension TimeOfDay {
    /// 날짜의 시:분을 꺼낸다 (초는 버린다).
    public init(date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        minutesSinceMidnight = (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    /// `day`와 같은 날의 이 시각. 시간 선택 컨트롤에 넘길 때 쓴다.
    public func date(on day: Date, calendar: Calendar) -> Date {
        let midnight = calendar.startOfDay(for: day)
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: midnight) ?? midnight
    }
}
