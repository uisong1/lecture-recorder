import Foundation

/// 노치 불빛이 알리는 수업 하나.
public struct NotchAlert<SubjectID: Hashable & Sendable>: Equatable, Sendable {
    public let subjectID: SubjectID
    public let classStart: Date
    public let classEnd: Date
    /// 이 시각이 지나면 불빛이 저절로 꺼진다.
    public let expiresAt: Date

    public init(subjectID: SubjectID, classStart: Date, classEnd: Date, expiresAt: Date) {
        self.subjectID = subjectID
        self.classStart = classStart
        self.classEnd = classEnd
        self.expiresAt = expiresAt
    }
}

extension ClassSchedule {
    /// 노치 불빛이 켜져 있는 시간(초). 수업 시작 `missedStartDelay` 뒤부터 이만큼 켜 둔다.
    public static var notchAlertDuration: TimeInterval { 10 * 60 }

    /// 지금 노치 불빛을 켜야 하는 수업. 없으면 nil.
    /// - 수업 시작 `delay` 뒤부터 `duration` 동안, 수업이 끝나기 전일 때만 켠다 (시작 시각은 포함, 끝 시각은 제외).
    /// - 지금 녹음 중이거나, 같은 과목의 녹음이 이 수업 시작 `leadMinutes`분 전부터 종료 전 사이에 있으면 켜지 않는다.
    /// - `dismissedStarts`에 시작 시각이 있는 수업(이미 불빛을 눌렀거나 끈 수업)은 다시 켜지 않는다.
    /// - 둘 이상이 겹치면 시작이 늦은 수업을 보인다.
    public func activeNotchAlert(
        now: Date,
        calendar: Calendar,
        recorded: [(subjectID: SubjectID, startedAt: Date)] = [],
        isRecording: Bool,
        dismissedStarts: Set<Date> = [],
        delay: TimeInterval = ClassSchedule.missedStartDelay,
        duration: TimeInterval = ClassSchedule.notchAlertDuration,
        leadMinutes: Int = ClassSchedule.defaultLeadMinutes
    ) -> NotchAlert<SubjectID>? {
        guard !isRecording else { return nil }
        let lead = Double(max(leadMinutes, 0) * 60)
        let candidates = todaysClasses(now: now, calendar: calendar).compactMap { entry -> NotchAlert<SubjectID>? in
            let from = entry.start.addingTimeInterval(delay)
            let until = min(from.addingTimeInterval(duration), entry.end)
            guard now >= from, now < until else { return nil }
            if dismissedStarts.contains(entry.start) { return nil }
            let earliest = entry.start.addingTimeInterval(-lead)
            let alreadyRecorded = recorded.contains {
                $0.subjectID == entry.subjectID && $0.startedAt >= earliest && $0.startedAt < entry.end
            }
            if alreadyRecorded { return nil }
            return NotchAlert(subjectID: entry.subjectID, classStart: entry.start, classEnd: entry.end, expiresAt: until)
        }
        return candidates.max { $0.classStart < $1.classStart }
    }
}
