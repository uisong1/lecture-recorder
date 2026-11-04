import Foundation
import Testing
@testable import LectureCore

@Suite struct MissingClassesTests {
    // 2026-03-02는 월요일이다.
    let schedule: ClassSchedule<String>

    init() throws {
        schedule = ClassSchedule(entries: [
            .init(period: try period(.monday, (9, 0), (10, 15)), subjectID: "운영체제"),
            .init(period: try period(.wednesday, (14, 0), (15, 15)), subjectID: "선형대수"),
        ])
    }

    func missing(recorded: [Date] = [], skipped: Set<Date> = [], now: Date = date(2026, 3, 6, 12, 0), daysBack: Int = 7) -> [MissingClass<String>] {
        schedule.missingClasses(recordedStarts: recorded, skipped: skipped, now: now, daysBack: daysBack, calendar: seoulCalendar)
    }

    @Test func 녹음이_없으면_지난_수업을_최근_것부터_돌려준다() {
        let result = missing()
        #expect(result.map(\.subjectID) == ["선형대수", "운영체제"])
        #expect(result[0].start == date(2026, 3, 4, 14, 0))
        #expect(result[0].end == date(2026, 3, 4, 15, 15))
        #expect(result[1].start == date(2026, 3, 2, 9, 0))
    }

    @Test func 수업_시간에_시작한_녹음이_있으면_뺀다() {
        let result = missing(recorded: [date(2026, 3, 2, 9, 2)])
        #expect(result.map(\.subjectID) == ["선형대수"])
    }

    @Test func 과목이_다르게_분류된_녹음도_그_시간이면_있는_것으로_본다() {
        // 시간만 본다: 미분류 녹음이어도 수업 시간에 녹음했다.
        let result = missing(recorded: [date(2026, 3, 4, 14, 5)])
        #expect(result.map(\.subjectID) == ["운영체제"])
    }

    @Test func 시작_30분_전_정각의_녹음은_있는_것으로_본다() {
        #expect(missing(recorded: [date(2026, 3, 2, 8, 30)]).map(\.subjectID) == ["선형대수"])
        #expect(missing(recorded: [date(2026, 3, 2, 8, 29)]).map(\.subjectID) == ["선형대수", "운영체제"])
    }

    @Test func 수업_종료_정각에_시작한_녹음은_그_수업_것이_아니다() {
        #expect(missing(recorded: [date(2026, 3, 2, 10, 15)]).map(\.subjectID).contains("운영체제"))
        #expect(!missing(recorded: [date(2026, 3, 2, 10, 14)]).map(\.subjectID).contains("운영체제"))
    }

    @Test func 수업이_끝나기_전에는_빠진_것이_아니다() {
        // 종료 정각이면 끝난 것이다. 1분 전이면 아직 수업 중이다.
        // 지난주 월요일 수업은 조회 기간에서 빼고 그날만 본다.
        #expect(missing(now: date(2026, 3, 2, 10, 15), daysBack: 3).map(\.subjectID) == ["운영체제"])
        #expect(missing(now: date(2026, 3, 2, 10, 14), daysBack: 3).isEmpty)
    }

    @Test func 조회_기간_밖의_수업은_넣지_않는다() {
        // 오늘(3/6)부터 4일 전(3/2 월요일)까지는 포함하고, 3일 전(3/3)까지만 보면 월요일 수업은 빠진다.
        #expect(missing(daysBack: 4).map(\.subjectID) == ["선형대수", "운영체제"])
        #expect(missing(daysBack: 3).map(\.subjectID) == ["선형대수"])
        #expect(missing(daysBack: 0).isEmpty)
        #expect(missing(daysBack: -1).isEmpty)
    }

    @Test func 사용자가_건너뛴_수업은_뺀다() {
        let result = missing(skipped: [date(2026, 3, 4, 14, 0)])
        #expect(result.map(\.subjectID) == ["운영체제"])
    }

    @Test func 시간표가_비어_있으면_빈_목록이다() {
        let empty = ClassSchedule<String>()
        #expect(empty.missingClasses(recordedStarts: [], now: date(2026, 3, 6, 12, 0), calendar: seoulCalendar).isEmpty)
    }

    @Test func 여러_주에_걸쳐_같은_요일_수업을_모두_찾는다() {
        let result = missing(now: date(2026, 3, 12, 12, 0), daysBack: 14)
        #expect(result.filter { $0.subjectID == "운영체제" }.map(\.start) == [date(2026, 3, 9, 9, 0), date(2026, 3, 2, 9, 0)])
    }
}
