#if canImport(SwiftData)
import Foundation
import SwiftData

/// 과목.
@Model
public final class Subject {
    public var name: String
    public var colorRawValue: String
    @Relationship(deleteRule: .cascade, inverse: \TimeSlot.subject)
    public var timeSlots: [TimeSlot] = []

    public init(name: String, color: SubjectColor = .blue) {
        self.name = name
        self.colorRawValue = color.rawValue
    }

    public var color: SubjectColor {
        get { SubjectColor(rawValue: colorRawValue) ?? .gray }
        set { colorRawValue = newValue.rawValue }
    }
}

/// 시간표 칸. 값 검증은 `ClassPeriod`가 맡는다.
@Model
public final class TimeSlot {
    public var weekdayRawValue: Int
    public var startMinutes: Int
    public var endMinutes: Int
    public var subject: Subject?

    public init(_ period: ClassPeriod, subject: Subject? = nil) {
        weekdayRawValue = period.weekday.rawValue
        startMinutes = period.start.minutesSinceMidnight
        endMinutes = period.end.minutesSinceMidnight
        self.subject = subject
    }

    /// 종료가 시작보다 빠르면 `ClassPeriod.ValidationError`를 던진다.
    public convenience init(weekday: Weekday, start: TimeOfDay, end: TimeOfDay, subject: Subject? = nil) throws(ClassPeriod.ValidationError) {
        self.init(try ClassPeriod(weekday: weekday, start: start, end: end), subject: subject)
    }

    /// 저장된 값이 깨졌으면 nil.
    public var period: ClassPeriod? {
        guard let weekday = Weekday(rawValue: weekdayRawValue),
              let start = TimeOfDay(minutesSinceMidnight: startMinutes),
              let end = TimeOfDay(minutesSinceMidnight: endMinutes)
        else { return nil }
        return try? ClassPeriod(weekday: weekday, start: start, end: end)
    }
}
#endif
