import Foundation
import Testing
@testable import LectureCore

@Suite struct NextClassTests {
    let schedule: ClassSchedule<String>

    init() throws {
        schedule = ClassSchedule(entries: [
            .init(period: try period(.monday, (9, 0), (10, 15)), subjectID: "운영체제"),
            .init(period: try period(.monday, (10, 15), (11, 30)), subjectID: "자료구조"),
            .init(period: try period(.monday, (11, 30), (12, 45)), subjectID: "자료구조"),
            .init(period: try period(.monday, (14, 0), (15, 15)), subjectID: "선형대수"),
        ])
    }

    func next(at now: Date, end: Date = date(2026, 3, 2, 10, 15)) -> String? {
        schedule.nextClassStarted(replacing: "운영체제", classEnd: end, now: now, calendar: seoulCalendar)
    }

    @Test func 다음_수업_시작_정각에_알린다() {
        #expect(next(at: date(2026, 3, 2, 10, 15)) == "자료구조")
    }

    @Test func 다음_수업_시작_1초_전에는_알리지_않는다() {
        #expect(next(at: date(2026, 3, 2, 10, 14, second: 59)) == nil)
    }

    @Test func 수업이_이어지는_동안_계속_알린다() {
        #expect(next(at: date(2026, 3, 2, 11, 0)) == "자료구조")
    }

    @Test func 쉬는_시간에는_알리지_않는다() {
        // 자료구조가 끝나고 선형대수가 시작하기 전.
        let end = date(2026, 3, 2, 12, 45)
        let result = schedule.nextClassStarted(replacing: "자료구조", classEnd: end, now: date(2026, 3, 2, 13, 0), calendar: seoulCalendar)
        #expect(result == nil)
    }

    @Test func 쉬는_시간_뒤_다음_수업이_시작하면_알린다() {
        let end = date(2026, 3, 2, 12, 45)
        let result = schedule.nextClassStarted(replacing: "자료구조", classEnd: end, now: date(2026, 3, 2, 14, 0), calendar: seoulCalendar)
        #expect(result == "선형대수")
    }

    @Test func 같은_과목_연강은_알리지_않는다() {
        let end = date(2026, 3, 2, 12, 45)
        let result = schedule.nextClassStarted(replacing: "자료구조", classEnd: end, now: date(2026, 3, 2, 11, 30), calendar: seoulCalendar)
        #expect(result == nil)
    }

    @Test func 다음_수업이_없으면_알리지_않는다() {
        let end = date(2026, 3, 2, 15, 15)
        let result = schedule.nextClassStarted(replacing: "선형대수", classEnd: end, now: date(2026, 3, 2, 15, 30), calendar: seoulCalendar)
        #expect(result == nil)
    }

    @Test func 수업이_아직_안_끝났으면_알리지_않는다() {
        #expect(next(at: date(2026, 3, 2, 10, 0), end: date(2026, 3, 2, 10, 30)) == nil)
    }

    @Test func 다음날의_수업은_알리지_않는다() throws {
        let weekly = ClassSchedule<String>(entries: [
            .init(period: try period(.tuesday, (10, 15), (11, 30)), subjectID: "자료구조"),
        ])
        let result = weekly.nextClassStarted(replacing: "운영체제", classEnd: date(2026, 3, 2, 10, 15), now: date(2026, 3, 3, 10, 20), calendar: seoulCalendar)
        #expect(result == nil)
    }

    @Test func 안내_문구() {
        let notice = NextClassNotice(subjectName: "자료구조")
        #expect(notice.message == "자료구조 수업이 시작됐습니다")
        #expect(notice.buttonTitle == "정지하고 자료구조 녹음 시작")
    }
}
