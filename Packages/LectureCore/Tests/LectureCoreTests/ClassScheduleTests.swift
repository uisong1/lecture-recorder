import Foundation
import Testing
@testable import LectureCore

/// 테스트용 고정 달력. 2026-03-02는 월요일.
let seoulCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .gmt
    return calendar
}()

func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, second: Int = 0) -> Date {
    let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
    guard let date = seoulCalendar.date(from: components) else {
        fatalError("잘못된 테스트 날짜")
    }
    return date
}

func period(_ weekday: Weekday, _ start: (Int, Int), _ end: (Int, Int)) throws -> ClassPeriod {
    try ClassPeriod(weekday: weekday, start: TimeOfDay(hour: start.0, minute: start.1), end: TimeOfDay(hour: end.0, minute: end.1))
}

@Suite struct ClassScheduleTests {
    let schedule: ClassSchedule<String>

    init() throws {
        schedule = ClassSchedule(entries: [
            .init(period: try period(.monday, (9, 0), (10, 15)), subjectID: "운영체제"),
            .init(period: try period(.monday, (10, 30), (11, 45)), subjectID: "자료구조"),
            .init(period: try period(.wednesday, (10, 30), (11, 45)), subjectID: "자료구조"),
            .init(period: try period(.friday, (13, 0), (16, 0)), subjectID: "실험"),
        ])
    }

    @Test func 월요일_10시40분은_자료구조() {
        #expect(schedule.classify(at: date(2026, 3, 2, 10, 40), calendar: seoulCalendar) == .subject("자료구조"))
    }

    @Test func 수업_없는_시간은_미분류() {
        #expect(schedule.classify(at: date(2026, 3, 2, 12, 0), calendar: seoulCalendar) == .unclassified)
    }

    @Test func 쉬는_시간은_미분류() {
        #expect(schedule.classify(at: date(2026, 3, 2, 10, 20), calendar: seoulCalendar) == .unclassified)
    }

    @Test func 시작_정각은_그_수업에_포함된다() {
        #expect(schedule.classify(at: date(2026, 3, 2, 10, 30), calendar: seoulCalendar) == .subject("자료구조"))
        #expect(schedule.classify(at: date(2026, 3, 2, 9, 0), calendar: seoulCalendar) == .subject("운영체제"))
    }

    @Test func 종료_정각은_그_수업에_포함되지_않는다() {
        #expect(schedule.classify(at: date(2026, 3, 2, 11, 45), calendar: seoulCalendar) == .unclassified)
        #expect(schedule.classify(at: date(2026, 3, 2, 10, 15), calendar: seoulCalendar) == .unclassified)
    }

    @Test func 종료_1분_전은_포함된다() {
        #expect(schedule.classify(at: date(2026, 3, 2, 11, 44, second: 59), calendar: seoulCalendar) == .subject("자료구조"))
    }

    @Test func 다른_요일의_같은_시각은_미분류() {
        // 2026-03-03은 화요일: 월·수에만 있는 자료구조 시간이다.
        #expect(schedule.classify(at: date(2026, 3, 3, 10, 40), calendar: seoulCalendar) == .unclassified)
    }

    @Test func 같은_과목이_다른_요일에도_있으면_찾는다() {
        // 2026-03-04는 수요일.
        #expect(schedule.classify(at: date(2026, 3, 4, 11, 0), calendar: seoulCalendar) == .subject("자료구조"))
    }

    @Test func 주말은_미분류() {
        #expect(schedule.classify(at: date(2026, 3, 7, 10, 40), calendar: seoulCalendar) == .unclassified)
    }

    @Test func 빈_시간표는_항상_미분류() {
        let empty = ClassSchedule<String>()
        #expect(empty.classify(at: date(2026, 3, 2, 10, 40), calendar: seoulCalendar) == .unclassified)
    }

    @Test func 달력의_시간대를_따른다() {
        // 서울 월요일 10:40은 UTC로 01:40이다. UTC 달력으로는 수업 시간이 아니다.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        #expect(schedule.classify(at: date(2026, 3, 2, 10, 40), calendar: utc) == .unclassified)
    }
}
