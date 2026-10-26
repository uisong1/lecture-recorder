import Foundation

/// 수업이 시작됐는데 녹음을 안 하고 있을 때 한 번 더 알리는 알림 한 건.
public struct MissedStartReminder<SubjectID: Hashable & Sendable>: Equatable, Sendable {
    public let subjectID: SubjectID
    /// 알려 주는 수업의 시작 시각.
    public let classStart: Date
    /// 수업이 끝나는 시각 (연강이면 마지막 칸의 종료 시각).
    public let classEnd: Date
    /// 알림이 울리는 시각.
    public let fireDate: Date

    public init(subjectID: SubjectID, classStart: Date, classEnd: Date, fireDate: Date) {
        self.subjectID = subjectID
        self.classStart = classStart
        self.classEnd = classEnd
        self.fireDate = fireDate
    }
}

extension ClassSchedule {
    /// 수업이 시작되고 이 시간(초)이 지나도 녹음 중이 아니면 알린다.
    public static var missedStartDelay: TimeInterval { 5 * 60 }

    /// `now`가 속한 날의 남은 수업 중, 시작 `delay` 뒤에 알릴 것들을 울릴 시각 순으로 돌려준다.
    /// - 알림 시각이 `now`보다 뒤이고(정각이면 이미 지난 것으로 본다) 수업이 끝나기 전일 때만 포함한다.
    /// - 연강의 이어진 칸은 한 수업으로 보고 첫 칸에서만 알린다.
    /// - `recorded`에 같은 과목의 녹음이 이 수업 시작 `leadMinutes`분 전부터 수업 종료 전 사이에 시작된 것이 있으면 이미 녹음한 수업으로 보고 뺀다.
    public func missedStartReminders(
        now: Date,
        calendar: Calendar,
        recorded: [(subjectID: SubjectID, startedAt: Date)] = [],
        delay: TimeInterval = ClassSchedule.missedStartDelay,
        leadMinutes: Int = ClassSchedule.defaultLeadMinutes
    ) -> [MissedStartReminder<SubjectID>] {
        guard let weekday = Weekday(rawValue: calendar.component(.weekday, from: now)) else { return [] }
        let dayStart = calendar.startOfDay(for: now)
        let today = entries.filter { $0.period.weekday == weekday }
        let lead = Double(max(leadMinutes, 0) * 60)

        var reminders: [MissedStartReminder<SubjectID>] = []
        for entry in today {
            let isContinuation = today.contains { $0.subjectID == entry.subjectID && $0.period.end == entry.period.start }
            if isContinuation { continue }

            var last = entry
            while let next = today.first(where: { $0.subjectID == entry.subjectID && $0.period.start == last.period.end }) {
                last = next
            }
            guard let start = calendar.date(byAdding: .minute, value: entry.period.start.minutesSinceMidnight, to: dayStart),
                  let end = calendar.date(byAdding: .minute, value: last.period.end.minutesSinceMidnight, to: dayStart)
            else { continue }

            let fireDate = start.addingTimeInterval(delay)
            guard fireDate > now, fireDate < end else { continue }

            let earliest = start.addingTimeInterval(-lead)
            let alreadyRecorded = recorded.contains {
                $0.subjectID == entry.subjectID && $0.startedAt >= earliest && $0.startedAt < end
            }
            if alreadyRecorded { continue }

            reminders.append(MissedStartReminder(subjectID: entry.subjectID, classStart: start, classEnd: end, fireDate: fireDate))
        }
        return reminders.sorted { $0.fireDate < $1.fireDate }
    }
}
