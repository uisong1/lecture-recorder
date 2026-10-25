import Foundation
import Testing
@testable import LectureCore

@Suite struct TimeOfDayDateTests {
    @Test func 날짜에서_시와_분을_꺼낸다() {
        let time = TimeOfDay(date: date(2026, 3, 2, 14, 35, second: 50), calendar: seoulCalendar)
        #expect(time.description == "14:35")
    }

    @Test func 같은_날의_날짜로_바꾼다() throws {
        let day = date(2026, 3, 2, 23, 59)
        let result = try TimeOfDay(hour: 9, minute: 5).date(on: day, calendar: seoulCalendar)
        #expect(result == date(2026, 3, 2, 9, 5))
    }
}
