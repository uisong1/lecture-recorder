import Foundation

/// 매주 되풀이되는 "수업이 곧 시작됩니다" 알림 한 건.
public struct ClassReminder<SubjectID: Hashable & Sendable>: Hashable, Sendable {
    public let subjectID: SubjectID
    /// 알림이 울리는 요일. 수업 시작이 자정 직후면 수업 요일의 전날이다.
    public let weekday: Weekday
    /// 알림이 울리는 시각.
    public let time: TimeOfDay
    /// 알려 주는 수업의 시작 시각.
    public let classStart: TimeOfDay

    public init(subjectID: SubjectID, weekday: Weekday, time: TimeOfDay, classStart: TimeOfDay) {
        self.subjectID = subjectID
        self.weekday = weekday
        self.time = time
        self.classStart = classStart
    }

    /// `now` 다음에 이 알림이 울릴 시각.
    public func nextFireDate(after now: Date, calendar: Calendar) -> Date? {
        let components = DateComponents(hour: time.hour, minute: time.minute, second: 0, weekday: weekday.rawValue)
        return calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime)
    }
}

extension ClassSchedule {
    /// 수업 시작 몇 분 전에 알릴지의 기본값.
    public static var defaultReminderLeadMinutes: Int { 2 }

    /// 시간표의 모든 수업에 대한 주간 알림. 요일·시각 순으로 돌려준다.
    /// 같은 과목이 이어서 붙은 칸(앞 칸이 끝나는 시각에 시작하는 칸)은 한 수업으로 보고 알리지 않는다.
    public func weeklyReminders(leadMinutes: Int = ClassSchedule.defaultReminderLeadMinutes) -> [ClassReminder<SubjectID>] {
        let lead = max(leadMinutes, 0)
        let reminders = entries.compactMap { entry -> ClassReminder<SubjectID>? in
            let isContinuation = entries.contains {
                $0.subjectID == entry.subjectID && $0.period.weekday == entry.period.weekday && $0.period.end == entry.period.start
            }
            if isContinuation { return nil }

            var minutes = entry.period.start.minutesSinceMidnight - lead
            var weekday = entry.period.weekday
            if minutes < 0 {
                // 자정 직후에 시작하는 수업은 전날 밤에 알린다.
                minutes += 24 * 60
                weekday = weekday.previous
            }
            guard let time = TimeOfDay(minutesSinceMidnight: minutes) else { return nil }
            return ClassReminder(subjectID: entry.subjectID, weekday: weekday, time: time, classStart: entry.period.start)
        }
        return reminders.sorted { ($0.weekday, $0.time) < ($1.weekday, $1.time) }
    }
}
