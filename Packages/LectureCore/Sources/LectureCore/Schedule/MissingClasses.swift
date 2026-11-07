import Foundation

/// 시간표상 수업이 있었는데 녹음이 없는 날 하나.
public struct MissingClass<SubjectID: Hashable & Sendable>: Hashable, Sendable {
    public let subjectID: SubjectID
    /// 그날 수업이 시작한 시각.
    public let start: Date
    /// 그날 수업이 끝난 시각.
    public let end: Date

    public init(subjectID: SubjectID, start: Date, end: Date) {
        self.subjectID = subjectID
        self.start = start
        self.end = end
    }
}

extension ClassSchedule {
    /// 녹음이 있는 것으로 보는 범위: 수업 시작 이만큼 전부터 수업 끝까지 시작한 녹음.
    public static var defaultCoverLeadMinutes: Int { 30 }

    /// 최근 `daysBack`일 동안 시간표상 수업이 이미 끝났는데 그 시간에 시작한 녹음이 없는 수업들. 최근 것이 앞에 온다.
    ///
    /// - `recordedStarts`: 기존 녹음들이 시작한 시각. 과목이 달라도(미분류여도) 그 시간에 녹음했으면 있는 것으로 본다.
    /// - `skipped`: 사용자가 "휴강·불필요"로 표시한 수업의 시작 시각. 목록에서 뺀다.
    /// - 수업이 끝나기 전(종료 정각 포함)이면 아직 빠진 것이 아니므로 넣지 않는다.
    public func missingClasses(
        recordedStarts: [Date],
        skipped: Set<Date> = [],
        now: Date,
        daysBack: Int = 28,
        calendar: Calendar,
        coverLeadMinutes: Int = ClassSchedule.defaultCoverLeadMinutes
    ) -> [MissingClass<SubjectID>] {
        guard daysBack >= 0 else { return [] }
        let today = calendar.startOfDay(for: now)
        var result: [MissingClass<SubjectID>] = []
        for offset in 0...daysBack {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let weekdayValue = calendar.component(.weekday, from: day)
            for entry in entries where entry.period.weekday.rawValue == weekdayValue {
                guard let start = Self.time(entry.period.start, on: day, calendar: calendar),
                      let end = Self.time(entry.period.end, on: day, calendar: calendar),
                      end <= now,
                      !skipped.contains(start)
                else { continue }
                let coverStart = start.addingTimeInterval(-Double(max(coverLeadMinutes, 0)) * 60)
                let covered = recordedStarts.contains { coverStart <= $0 && $0 < end }
                if !covered {
                    result.append(MissingClass(subjectID: entry.subjectID, start: start, end: end))
                }
            }
        }
        return result.sorted { $0.start > $1.start }
    }

    private static func time(_ time: TimeOfDay, on day: Date, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day)
    }
}
