import Foundation
import Testing
@testable import LectureCore

@Suite struct ClassOverrunTests {
    let schedule: ClassSchedule<String>

    init() throws {
        schedule = ClassSchedule(entries: [
            .init(period: try period(.monday, (9, 0), (10, 15)), subjectID: "운영체제"),
            .init(period: try period(.monday, (10, 30), (11, 45)), subjectID: "자료구조"),
            .init(period: try period(.monday, (11, 45), (12, 30)), subjectID: "자료구조"),
            .init(period: try period(.wednesday, (10, 30), (11, 45)), subjectID: "자료구조"),
        ])
    }

    @Test func 수업_중에_시작하면_그_수업의_종료_시각이다() {
        let end = schedule.classEnd(of: "운영체제", startedAt: date(2026, 3, 2, 9, 5), calendar: seoulCalendar)
        #expect(end == date(2026, 3, 2, 10, 15))
    }

    @Test func 수업_시작_정각과_10분_전도_그_수업이다() {
        #expect(schedule.classEnd(of: "운영체제", startedAt: date(2026, 3, 2, 9, 0), calendar: seoulCalendar) == date(2026, 3, 2, 10, 15))
        #expect(schedule.classEnd(of: "운영체제", startedAt: date(2026, 3, 2, 8, 50), calendar: seoulCalendar) == date(2026, 3, 2, 10, 15))
        #expect(schedule.classEnd(of: "운영체제", startedAt: date(2026, 3, 2, 8, 49, second: 59), calendar: seoulCalendar) == nil)
    }

    @Test func 종료_정각에_시작하면_그_수업이_아니다() {
        #expect(schedule.classEnd(of: "운영체제", startedAt: date(2026, 3, 2, 10, 15), calendar: seoulCalendar) == nil)
    }

    @Test func 같은_과목이_이어지는_연강은_마지막_칸의_종료_시각이다() {
        let end = schedule.classEnd(of: "자료구조", startedAt: date(2026, 3, 2, 10, 35), calendar: seoulCalendar)
        #expect(end == date(2026, 3, 2, 12, 30))
    }

    @Test func 다른_요일의_수업이나_없는_과목은_nil() {
        #expect(schedule.classEnd(of: "운영체제", startedAt: date(2026, 3, 4, 9, 5), calendar: seoulCalendar) == nil)
        #expect(schedule.classEnd(of: "실험", startedAt: date(2026, 3, 2, 9, 5), calendar: seoulCalendar) == nil)
    }

    @Test func 수업_안내는_종료_10분_후_정각부터_나온다() {
        let end = date(2026, 3, 2, 10, 15)
        #expect(ClassOverrunAdvice.notice(subjectName: "운영체제", classEnd: end, now: date(2026, 3, 2, 10, 24, second: 59)) == nil)
        #expect(ClassOverrunAdvice.notice(subjectName: "운영체제", classEnd: end, now: date(2026, 3, 2, 10, 25)) != nil)
    }

    @Test func 안내_문구에_과목과_지난_시간이_들어간다() {
        let notice = ClassOverrunAdvice.notice(subjectName: "운영체제", classEnd: date(2026, 3, 2, 10, 15), now: date(2026, 3, 2, 10, 37))
        #expect(notice == "운영체제 수업이 22분 전에 끝났습니다. 녹음을 정지할까요?")
    }

    @Test func 수업을_모르면_안내하지_않는다() {
        #expect(ClassOverrunAdvice.notice(subjectName: "미분류", classEnd: nil, now: date(2026, 3, 2, 23, 0)) == nil)
    }
}
