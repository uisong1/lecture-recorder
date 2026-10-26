import Foundation
import Testing
@testable import LectureCore

@Suite struct MissedStartTests {
    /// 월 10:00~11:15 자료구조, 월 13:00~14:00 + 14:00~15:00 알고리즘(연강), 화 10:00~11:00 운영체제.
    let schedule: ClassSchedule<String>

    init() throws {
        schedule = ClassSchedule<String>(entries: [
            .init(period: try period(.monday, (10, 0), (11, 15)), subjectID: "자료구조"),
            .init(period: try period(.monday, (13, 0), (14, 0)), subjectID: "알고리즘"),
            .init(period: try period(.monday, (14, 0), (15, 0)), subjectID: "알고리즘"),
            .init(period: try period(.tuesday, (10, 0), (11, 0)), subjectID: "운영체제"),
        ])
    }

    private func reminders(
        at now: Date,
        recorded: [(subjectID: String, startedAt: Date)] = []
    ) -> [MissedStartReminder<String>] {
        schedule.missedStartReminders(now: now, calendar: seoulCalendar, recorded: recorded)
    }

    @Test func 기본_기준은_5분이다() {
        #expect(ClassSchedule<String>.missedStartDelay == 300)
    }

    @Test func 수업_시작_5분_뒤_시각에_울린다() throws {
        let first = try #require(reminders(at: date(2026, 3, 2, 8, 0)).first)
        #expect(first.subjectID == "자료구조")
        #expect(first.fireDate == date(2026, 3, 2, 10, 5))
        #expect(first.classStart == date(2026, 3, 2, 10, 0))
        #expect(first.classEnd == date(2026, 3, 2, 11, 15))
    }

    @Test func 오늘_남은_수업만_시간_순으로_예약한다() {
        let all = reminders(at: date(2026, 3, 2, 8, 0))
        #expect(all.map(\.subjectID) == ["자료구조", "알고리즘"])
        // 화요일 수업은 오늘 것이 아니다.
        #expect(reminders(at: date(2026, 3, 2, 11, 0)).map(\.subjectID) == ["알고리즘"])
    }

    @Test func 시작_4분_59초는_아직_예약하고_5분_정각은_예약하지_않는다() {
        // 알림 시각이 1초 뒤라 아직 울릴 수 있다.
        #expect(reminders(at: date(2026, 3, 2, 10, 4, second: 59)).first?.subjectID == "자료구조")
        // 정각이면 이미 지난 때라 예약하지 않는다.
        #expect(reminders(at: date(2026, 3, 2, 10, 5)).first?.subjectID != "자료구조")
    }

    @Test func 수업이_끝난_뒤에는_예약하지_않는다() {
        #expect(reminders(at: date(2026, 3, 2, 15, 0)).isEmpty)
        #expect(reminders(at: date(2026, 3, 2, 23, 0)).isEmpty)
    }

    @Test func 알림_시각에_수업이_이미_끝났으면_예약하지_않는다() throws {
        let short = ClassSchedule<String>(entries: [.init(period: try period(.monday, (10, 0), (10, 5)), subjectID: "짧은수업")])
        #expect(short.missedStartReminders(now: date(2026, 3, 2, 8, 0), calendar: seoulCalendar).isEmpty)
        let justOver = ClassSchedule<String>(entries: [.init(period: try period(.monday, (10, 0), (10, 6)), subjectID: "짧은수업")])
        #expect(justOver.missedStartReminders(now: date(2026, 3, 2, 8, 0), calendar: seoulCalendar).count == 1)
    }

    @Test func 연강은_첫_칸에서_한_번만_예약한다() {
        let algorithm = reminders(at: date(2026, 3, 2, 8, 0)).filter { $0.subjectID == "알고리즘" }
        #expect(algorithm.count == 1)
        #expect(algorithm.first?.fireDate == date(2026, 3, 2, 13, 5))
        #expect(algorithm.first?.classEnd == date(2026, 3, 2, 15, 0))
    }

    @Test func 이미_그_수업을_녹음했으면_뺀다() {
        let recorded = [(subjectID: "자료구조", startedAt: date(2026, 3, 2, 10, 1))]
        #expect(reminders(at: date(2026, 3, 2, 8, 0), recorded: recorded).map(\.subjectID) == ["알고리즘"])
    }

    @Test func 수업_10분_전에_시작한_녹음도_그_수업으로_본다() {
        let early = [(subjectID: "자료구조", startedAt: date(2026, 3, 2, 9, 50))]
        #expect(reminders(at: date(2026, 3, 2, 8, 0), recorded: early).map(\.subjectID) == ["알고리즘"])
        let tooEarly = [(subjectID: "자료구조", startedAt: date(2026, 3, 2, 9, 49, second: 59))]
        #expect(reminders(at: date(2026, 3, 2, 8, 0), recorded: tooEarly).map(\.subjectID) == ["자료구조", "알고리즘"])
    }

    @Test func 다른_과목의_녹음은_이_수업을_녹음한_것으로_치지_않는다() {
        let other = [(subjectID: "운영체제", startedAt: date(2026, 3, 2, 10, 30))]
        #expect(reminders(at: date(2026, 3, 2, 8, 0), recorded: other).count == 2)
    }

    @Test func 연강_뒤쪽_칸에_시작한_녹음도_그_수업을_녹음한_것이다() {
        let late = [(subjectID: "알고리즘", startedAt: date(2026, 3, 2, 14, 30))]
        #expect(reminders(at: date(2026, 3, 2, 8, 0), recorded: late).map(\.subjectID) == ["자료구조"])
    }

    @Test func 수업이_없는_날은_비어_있다() {
        #expect(reminders(at: date(2026, 3, 4, 8, 0)).isEmpty)  // 수요일
    }
}
