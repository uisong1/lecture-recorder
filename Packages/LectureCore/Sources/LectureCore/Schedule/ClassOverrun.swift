import Foundation

extension ClassSchedule {
    /// 수업이 끝난 뒤 이 시간(분)이 지나도 녹음 중이면 알린다.
    public static var overrunGraceMinutes: Int { 10 }

    /// `startedAt`에 시작한 `subjectID` 수업이 끝나는 시각. 그 수업이 없으면 nil.
    /// 시작 정각이 수업 중이거나 `leadMinutes`분 안에 시작하는 칸을 그 수업으로 보고(분류와 같은 기준),
    /// 같은 과목이 끝나자마자 이어지는 칸(연강)은 하나로 묶어 마지막 칸의 종료 시각을 쓴다.
    public func classEnd(
        of subjectID: SubjectID,
        startedAt: Date,
        calendar: Calendar,
        leadMinutes: Int = ClassSchedule.defaultLeadMinutes
    ) -> Date? {
        let components = calendar.dateComponents([.weekday, .hour, .minute, .second], from: startedAt)
        guard let weekdayValue = components.weekday,
              let weekday = Weekday(rawValue: weekdayValue),
              let hour = components.hour,
              let minute = components.minute
        else { return nil }
        let seconds = hour * 3600 + minute * 60 + (components.second ?? 0)
        let lead = max(leadMinutes, 0) * 60

        let mine = entries.filter { $0.subjectID == subjectID && $0.period.weekday == weekday }
        guard var current = mine
            .filter { $0.period.start.minutesSinceMidnight * 60 - lead <= seconds && seconds < $0.period.end.minutesSinceMidnight * 60 }
            .min(by: { $0.period.start < $1.period.start })
        else { return nil }
        while let next = mine.first(where: { $0.period.start == current.period.end }) {
            current = next
        }
        let end = current.period.end.minutesSinceMidnight
        return calendar.date(bySettingHour: end / 60, minute: end % 60, second: 0, of: startedAt)
    }
}

/// 수업이 끝났는데 녹음이 계속될 때 보여 줄 안내.
public enum ClassOverrunAdvice {
    /// `classEnd`에서 `graceMinutes`분이 지났으면 안내 문구, 아직이거나 수업을 모르면 nil. 종료 후 여유 정각부터 알린다.
    public static func notice(
        subjectName: String,
        classEnd: Date?,
        now: Date,
        graceMinutes: Int = ClassSchedule<String>.overrunGraceMinutes
    ) -> String? {
        guard let classEnd else { return nil }
        let elapsed = now.timeIntervalSince(classEnd)
        guard elapsed >= Double(graceMinutes * 60) else { return nil }
        return "\(subjectName) 수업이 \(Int(elapsed) / 60)분 전에 끝났습니다. 녹음을 정지할까요?"
    }
}
