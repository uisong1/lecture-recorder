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
    /// 노치 불빛이 켜지는 때. 수업 시작 정각부터 켠다 (2026-11-10 사용자 결정). 시작 알림(`missedStartDelay`)과 따로다.
    public static var notchAlertDelay: TimeInterval { 0 }

    /// 지금 노치 불빛을 켜야 하는 수업. 없으면 nil.
    /// - 수업 시작 `delay`(기본 정각) 뒤부터 수업이 끝나기 전까지 켠다 (시작 시각은 포함, 끝 시각은 제외). 시간이 지났다고 저절로 꺼지지 않고, 사용자가 누르거나 끄거나 녹음을 시작해야 꺼진다.
    /// - 지금 녹음 중이거나, 같은 과목의 녹음이 이 수업 시작 `leadMinutes`분 전부터 종료 전 사이에 있으면 켜지 않는다.
    /// - `dismissedStarts`에 시작 시각이 있는 수업(이미 불빛을 눌렀거나 끈 수업)은 다시 켜지 않는다.
    /// - 둘 이상이 겹치면 시작이 늦은 수업을 보인다.
    public func activeNotchAlert(
        now: Date,
        calendar: Calendar,
        recorded: [(subjectID: SubjectID, startedAt: Date)] = [],
        isRecording: Bool,
        dismissedStarts: Set<Date> = [],
        delay: TimeInterval = ClassSchedule.notchAlertDelay,
        leadMinutes: Int = ClassSchedule.defaultLeadMinutes
    ) -> NotchAlert<SubjectID>? {
        guard !isRecording else { return nil }
        let lead = Double(max(leadMinutes, 0) * 60)
        let candidates = todaysClasses(now: now, calendar: calendar).compactMap { entry -> NotchAlert<SubjectID>? in
            let from = entry.start.addingTimeInterval(delay)
            let until = entry.end
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

/// 노치 자리에 지금 무엇을 보일지. 녹음 중이면 날개, 녹음 전 수업이 있으면 배너, 아니면 아무것도 없다 (DECISIONS.md 2026-11-11).
public enum NotchDisplay: Equatable, Sendable {
    case none
    /// 수업이 시작됐는데 녹음 전이다. 파란 배너로 알린다.
    case alert(NotchAlertInfo)
    /// 녹음 중이다. 노치 양옆의 검은 날개에 빨간 막대를 보인다. 일시정지면 막대가 멈춘다.
    case recording(isPaused: Bool)

    /// 녹음 중이 배너보다 먼저다. 설정에서 노치 표시를 끄면 둘 다 보이지 않는다.
    public static func resolve(isEnabled: Bool, isRecording: Bool, isPaused: Bool, alert: NotchAlertInfo?) -> NotchDisplay {
        guard isEnabled else { return .none }
        if isRecording { return .recording(isPaused: isPaused) }
        if let alert { return .alert(alert) }
        return .none
    }
}
