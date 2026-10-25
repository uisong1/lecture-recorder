import Foundation

/// 녹음이 어느 과목에 속하는지 판별한 결과.
public enum SubjectClassification<SubjectID: Hashable & Sendable>: Hashable, Sendable {
    case subject(SubjectID)
    /// 수업이 없는 시간.
    case unclassified
}

/// 주간 시간표. 과목은 `SubjectID`로 가리킨다 (앱에서는 SwiftData의 `PersistentIdentifier`, 테스트에서는 문자열).
public struct ClassSchedule<SubjectID: Hashable & Sendable>: Sendable {
    public struct Entry: Hashable, Sendable {
        public let period: ClassPeriod
        public let subjectID: SubjectID

        public init(period: ClassPeriod, subjectID: SubjectID) {
            self.period = period
            self.subjectID = subjectID
        }
    }

    public private(set) var entries: [Entry]

    public enum ScheduleError: Error, Equatable {
        /// 같은 요일에 시간이 겹치는 칸이 이미 있음.
        case overlaps(with: Entry)
    }

    public init(entries: [Entry] = []) {
        self.entries = entries
    }

    /// 새 칸과 겹치는 기존 칸. 없으면 nil.
    public func conflict(for period: ClassPeriod) -> Entry? {
        entries.first { $0.period.overlaps(period) }
    }

    /// 칸을 추가한다. 같은 요일에 시간이 겹치면 거부한다 (과목이 같아도).
    public mutating func add(_ entry: Entry) throws(ScheduleError) {
        if let existing = conflict(for: entry.period) {
            throw .overlaps(with: existing)
        }
        entries.append(entry)
    }

    /// `now` 시각에 진행 중인 수업의 과목. 시작 정각은 포함, 종료 정각은 포함하지 않는다.
    public func classify(at now: Date, calendar: Calendar) -> SubjectClassification<SubjectID> {
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: now)
        guard let weekdayValue = components.weekday,
              let weekday = Weekday(rawValue: weekdayValue),
              let hour = components.hour,
              let minute = components.minute,
              let time = try? TimeOfDay(hour: hour, minute: minute)
        else { return .unclassified }

        guard let entry = entries.first(where: { $0.period.contains(weekday: weekday, time: time) }) else {
            return .unclassified
        }
        return .subject(entry.subjectID)
    }
}
