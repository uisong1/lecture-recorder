import Testing
@testable import LectureCore

@Suite struct TimeOfDayTests {
    @Test func 시와_분으로_만든다() throws {
        let time = try TimeOfDay(hour: 9, minute: 5)
        #expect(time.hour == 9)
        #expect(time.minute == 5)
        #expect(time.description == "09:05")
    }

    @Test(arguments: [(24, 0), (-1, 0), (10, 60), (10, -1)])
    func 범위를_벗어나면_오류(hour: Int, minute: Int) {
        #expect(throws: TimeOfDay.ValidationError.outOfRange(hour: hour, minute: minute)) {
            try TimeOfDay(hour: hour, minute: minute)
        }
    }

    @Test func 저장된_분_값에서_복원한다() {
        #expect(TimeOfDay(minutesSinceMidnight: 600)?.description == "10:00")
        #expect(TimeOfDay(minutesSinceMidnight: 1440) == nil)
    }
}

@Suite struct ClassPeriodTests {
    @Test func 요일과_시작_종료로_만든다() throws {
        let period = try ClassPeriod(weekday: .monday, start: TimeOfDay(hour: 10), end: TimeOfDay(hour: 11, minute: 15))
        #expect(period.weekday == .monday)
        #expect(period.start.description == "10:00")
        #expect(period.end.description == "11:15")
    }

    @Test func 종료가_시작보다_빠르면_오류() throws {
        let start = try TimeOfDay(hour: 11)
        let end = try TimeOfDay(hour: 10)
        #expect(throws: ClassPeriod.ValidationError.endNotAfterStart) {
            try ClassPeriod(weekday: .monday, start: start, end: end)
        }
    }

    @Test func 종료와_시작이_같아도_오류() throws {
        let time = try TimeOfDay(hour: 10)
        #expect(throws: ClassPeriod.ValidationError.endNotAfterStart) {
            try ClassPeriod(weekday: .monday, start: time, end: time)
        }
    }
}

@Suite struct WeekdayTests {
    @Test func 원시값은_Calendar_weekday와_같다() {
        #expect(Weekday.sunday.rawValue == 1)
        #expect(Weekday.monday.rawValue == 2)
        #expect(Weekday.saturday.rawValue == 7)
    }

    @Test func 월요일부터_정렬된다() {
        #expect(Weekday.allCases.sorted() == Weekday.mondayFirst)
        #expect(Weekday.monday.shortName == "월")
    }
}

#if canImport(SwiftData)
@Suite struct SubjectModelTests {
    @Test func 과목은_이름과_색상을_가진다() {
        let subject = Subject(name: "자료구조", color: .green)
        #expect(subject.name == "자료구조")
        #expect(subject.color == .green)
        subject.color = .red
        #expect(subject.colorRawValue == "red")
    }

    @Test func 시간표_칸을_만든다() throws {
        let subject = Subject(name: "자료구조")
        let slot = try TimeSlot(weekday: .wednesday, start: TimeOfDay(hour: 13), end: TimeOfDay(hour: 14, minute: 30), subject: subject)
        #expect(slot.period?.weekday == .wednesday)
        #expect(slot.startMinutes == 13 * 60)
        #expect(slot.endMinutes == 14 * 60 + 30)
    }

    @Test func 시간표_칸의_종료가_시작보다_빠르면_오류() throws {
        let start = try TimeOfDay(hour: 14)
        let end = try TimeOfDay(hour: 13)
        #expect(throws: ClassPeriod.ValidationError.endNotAfterStart) {
            try TimeSlot(weekday: .wednesday, start: start, end: end)
        }
    }
}
#endif
