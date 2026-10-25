import Foundation
import Testing
@testable import LectureCore

@Suite struct RecordingFilterTests {
    /// 2026-03-30(월) 오후 3시.
    let now = date(2026, 3, 30, 15, 0)

    func matches(_ filter: RecordingFilter, title: String = "자료구조 3주차", at startedAt: Date? = nil) -> Bool {
        filter.matches(title: title, startedAt: startedAt ?? now, now: now, calendar: seoulCalendar)
    }

    @Test func 조건이_없으면_모두_통과한다() {
        let filter = RecordingFilter()
        #expect(!filter.isActive)
        #expect(matches(filter))
        #expect(matches(filter, at: date(2020, 1, 1, 0, 0)))
    }

    @Test func 제목의_일부로_찾는다() {
        #expect(matches(RecordingFilter(query: "자료")))
        #expect(matches(RecordingFilter(query: "3주차")))
        #expect(!matches(RecordingFilter(query: "알고리즘")))
    }

    @Test func 검색어의_앞뒤_공백과_대소문자는_무시한다() {
        #expect(matches(RecordingFilter(query: "  자료  ")))
        #expect(matches(RecordingFilter(query: "ai"), title: "AI 데이터 분석"))
    }

    @Test func 공백만_있는_검색어는_조건이_없는_것과_같다() {
        let filter = RecordingFilter(query: "   ")
        #expect(!filter.isActive)
        #expect(matches(filter))
    }

    @Test func 한글_조합_방식이_달라도_찾는다() {
        let decomposed = "자료구조".decomposedStringWithCanonicalMapping
        #expect(matches(RecordingFilter(query: "자료구조"), title: decomposed))
        #expect(matches(RecordingFilter(query: decomposed), title: "자료구조"))
    }

    @Test func 최근_7일은_오늘과_그_전_6일의_0시부터다() {
        let filter = RecordingFilter(period: .last7Days)
        #expect(filter.isActive)
        #expect(matches(filter, at: date(2026, 3, 24, 0, 0)))
        #expect(!matches(filter, at: date(2026, 3, 23, 23, 59, second: 59)))
        #expect(matches(filter, at: now))
    }

    @Test func 최근_30일은_오늘과_그_전_29일의_0시부터다() {
        let filter = RecordingFilter(period: .last30Days)
        #expect(matches(filter, at: date(2026, 3, 1, 0, 0)))
        #expect(!matches(filter, at: date(2026, 2, 28, 23, 59, second: 59)))
    }

    @Test func 지금보다_미래인_녹음도_기간에_들어간다() {
        #expect(matches(RecordingFilter(period: .last7Days), at: date(2026, 3, 31, 9, 0)))
    }

    @Test func 새벽에_보아도_오늘_0시를_기준으로_센다() {
        let earlyNow = date(2026, 3, 30, 0, 5)
        let filter = RecordingFilter(period: .last7Days)
        #expect(filter.matches(title: "녹음", startedAt: date(2026, 3, 24, 0, 0), now: earlyNow, calendar: seoulCalendar))
        #expect(!filter.matches(title: "녹음", startedAt: date(2026, 3, 23, 23, 0), now: earlyNow, calendar: seoulCalendar))
    }

    @Test func 검색어와_기간을_함께_걸면_둘_다_맞아야_한다() {
        let filter = RecordingFilter(query: "자료", period: .last7Days)
        #expect(matches(filter, at: date(2026, 3, 29, 10, 0)))
        #expect(!matches(filter, at: date(2026, 3, 1, 10, 0)))
        #expect(!matches(filter, title: "알고리즘", at: date(2026, 3, 29, 10, 0)))
    }

    // MARK: 안 들은 것만

    @Test func 안_들은_것만_켜면_조건이_걸린_것으로_본다() {
        #expect(RecordingFilter(unplayedOnly: true).isActive)
        #expect(!RecordingFilter(unplayedOnly: false).isActive)
    }

    @Test func 안_들은_것만_켜면_들은_녹음은_빠진다() {
        let filter = RecordingFilter(unplayedOnly: true)
        #expect(filter.matches(title: "녹음", startedAt: now, isUnplayed: true, now: now, calendar: seoulCalendar))
        #expect(!filter.matches(title: "녹음", startedAt: now, isUnplayed: false, now: now, calendar: seoulCalendar))
    }

    @Test func 안_들은_것만을_끄면_들은_녹음도_나온다() {
        let filter = RecordingFilter()
        #expect(filter.matches(title: "녹음", startedAt: now, isUnplayed: false, now: now, calendar: seoulCalendar))
    }

    @Test func 안_들은_것만은_검색어와_기간과_함께_적용된다() {
        let filter = RecordingFilter(query: "자료", period: .last7Days, unplayedOnly: true)
        let recent = date(2026, 3, 29, 10, 0)
        let old = date(2026, 3, 1, 10, 0)
        #expect(filter.matches(title: "자료구조", startedAt: recent, isUnplayed: true, now: now, calendar: seoulCalendar))
        #expect(!filter.matches(title: "운영체제", startedAt: recent, isUnplayed: true, now: now, calendar: seoulCalendar))
        #expect(!filter.matches(title: "자료구조", startedAt: old, isUnplayed: true, now: now, calendar: seoulCalendar))
        #expect(!filter.matches(title: "자료구조", startedAt: recent, isUnplayed: false, now: now, calendar: seoulCalendar))
    }

    @Test func 정렬_방향_이름과_저장값() {
        #expect(RecordingSortOrder.newestFirst.label == "최신순")
        #expect(RecordingSortOrder.oldestFirst.label == "오래된 순")
        #expect(RecordingSortOrder(rawValue: RecordingSortOrder.oldestFirst.rawValue) == .oldestFirst)
        #expect(RecordingSortOrder(rawValue: "엉뚱한 값") == nil)
    }
}
