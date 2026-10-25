import Foundation
import Testing
@testable import LectureCore

@Suite struct RecordingFileNameTests {
    func parse(_ name: String, year: Int? = 2026) -> Date? {
        RecordingFileName.startedAt(fromFileName: name, yearHint: year, calendar: seoulCalendar)
    }

    @Test func 지금_규칙의_이름을_읽는다() {
        #expect(parse("10-28 수 13-30.m4a") == date(2026, 10, 28, 13, 30))
    }

    @Test func 예전_규칙의_이름은_연도_힌트_없이도_읽는다() {
        #expect(parse("2026-03-02_1000.m4a", year: nil) == date(2026, 3, 2, 10, 0))
    }

    @Test func 같은_이름_번호는_무시한다() {
        #expect(parse("10-28 수 13-30_2.m4a") == date(2026, 10, 28, 13, 30))
    }

    @Test func 연도_힌트가_없으면_지금_규칙은_읽지_못한다() {
        #expect(parse("10-28 수 13-30.m4a", year: nil) == nil)
    }

    @Test(arguments: ["강의 녹음.m4a", "13-45 수 10-00.m4a", "02-30 월 10-00.m4a", "10-28 수 25-00.m4a", ""])
    func 규칙에_맞지_않으면_nil(name: String) {
        #expect(parse(name) == nil)
    }

    @Test func 학기_이름에서_연도를_읽는다() {
        #expect(RecordingFileName.year(fromSemester: "2026년 2학기") == 2026)
        #expect(RecordingFileName.year(fromSemester: "학기 미정") == nil)
    }
}
