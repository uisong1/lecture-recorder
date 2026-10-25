import Foundation

extension ClassSchedule {
    /// `subjectID` 수업을 녹음하던 중 다른 과목의 수업이 시작됐는지 판별한다. 시작됐으면 그 과목, 아니면 nil.
    ///
    /// - 녹음 중인 수업이 끝났고(`now >= classEnd`, 종료 정각 포함) 같은 날 다른 과목의 수업이 진행 중일 때만 돌려준다.
    ///   수업 시작 정각부터 진행 중이다.
    /// - 쉬는 시간(다음 수업이 아직 시작하지 않음)이나 같은 과목이 이어지는 연강, 수업 없는 시간에는 nil이다.
    public func nextClassStarted(
        replacing subjectID: SubjectID,
        classEnd: Date,
        now: Date,
        calendar: Calendar
    ) -> SubjectID? {
        guard now >= classEnd, calendar.isDate(now, inSameDayAs: classEnd) else { return nil }
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: now)
        guard let weekdayValue = components.weekday,
              let weekday = Weekday(rawValue: weekdayValue),
              let hour = components.hour,
              let minute = components.minute,
              let time = try? TimeOfDay(hour: hour, minute: minute),
              let current = entries.first(where: { $0.period.contains(weekday: weekday, time: time) }),
              current.subjectID != subjectID
        else { return nil }
        return current.subjectID
    }
}

/// 연강에서 다음 과목 수업이 시작됐을 때 녹음 화면에 보일 안내.
public struct NextClassNotice: Equatable, Sendable {
    public let subjectName: String

    public init(subjectName: String) {
        self.subjectName = subjectName
    }

    public var message: String { "\(subjectName) 수업이 시작됐습니다" }
    public var buttonTitle: String { "정지하고 \(subjectName) 녹음 시작" }
    public var notificationTitle: String { message }
    public var notificationBody: String { "앱에서 ‘\(buttonTitle)’을 누르면 한 번에 넘어갑니다." }
}
