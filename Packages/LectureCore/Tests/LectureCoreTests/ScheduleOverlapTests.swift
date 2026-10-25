import Testing
@testable import LectureCore

@Suite struct ScheduleOverlapTests {
    func makeSchedule() throws -> ClassSchedule<String> {
        var schedule = ClassSchedule<String>()
        try schedule.add(.init(period: try period(.monday, (10, 0), (11, 30)), subjectID: "자료구조"))
        return schedule
    }

    @Test func 겹치지_않으면_추가된다() throws {
        var schedule = try makeSchedule()
        try schedule.add(.init(period: try period(.monday, (13, 0), (14, 0)), subjectID: "운영체제"))
        #expect(schedule.entries.count == 2)
    }

    @Test func 일부가_겹치면_거부된다() throws {
        var schedule = try makeSchedule()
        let existing = try #require(schedule.entries.first)
        #expect(throws: ClassSchedule<String>.ScheduleError.overlaps(with: existing)) {
            try schedule.add(.init(period: try period(.monday, (11, 0), (12, 0)), subjectID: "운영체제"))
        }
        #expect(schedule.entries.count == 1)
    }

    @Test func 안에_완전히_들어가면_거부된다() throws {
        var schedule = try makeSchedule()
        #expect(throws: ClassSchedule<String>.ScheduleError.self) {
            try schedule.add(.init(period: try period(.monday, (10, 15), (10, 45)), subjectID: "운영체제"))
        }
    }

    @Test func 기존_칸을_감싸면_거부된다() throws {
        var schedule = try makeSchedule()
        #expect(throws: ClassSchedule<String>.ScheduleError.self) {
            try schedule.add(.init(period: try period(.monday, (9, 0), (12, 0)), subjectID: "운영체제"))
        }
    }

    @Test func 시간이_똑같으면_같은_과목이라도_거부된다() throws {
        var schedule = try makeSchedule()
        #expect(throws: ClassSchedule<String>.ScheduleError.self) {
            try schedule.add(.init(period: try period(.monday, (10, 0), (11, 30)), subjectID: "자료구조"))
        }
    }

    @Test func 끝나는_시각에_시작하는_칸은_겹치지_않는다() throws {
        var schedule = try makeSchedule()
        try schedule.add(.init(period: try period(.monday, (11, 30), (12, 30)), subjectID: "운영체제"))
        try schedule.add(.init(period: try period(.monday, (9, 0), (10, 0)), subjectID: "실험"))
        #expect(schedule.entries.count == 3)
    }

    @Test func 다른_요일의_같은_시간은_겹치지_않는다() throws {
        var schedule = try makeSchedule()
        try schedule.add(.init(period: try period(.tuesday, (10, 0), (11, 30)), subjectID: "운영체제"))
        #expect(schedule.entries.count == 2)
    }

    @Test func 겹치는_칸을_미리_찾는다() throws {
        let schedule = try makeSchedule()
        #expect(schedule.conflict(for: try period(.monday, (11, 0), (12, 0)))?.subjectID == "자료구조")
        #expect(schedule.conflict(for: try period(.monday, (11, 30), (12, 0))) == nil)
    }
}
