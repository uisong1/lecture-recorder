import Testing
@testable import LectureCore

@Suite struct BookmarkMatchSummaryTests {
    func summary(_ notes: [String]) -> BookmarkMatchSummary<String> {
        BookmarkMatchSummary(notes) { $0 }
    }

    @Test func 맞은_메모가_없으면_아무것도_보이지_않는다() {
        let result = summary([])
        #expect(result.shown.isEmpty)
        #expect(result.hiddenText == nil)
    }

    @Test func 두_개까지는_모두_보이고_접지_않는다() {
        let result = summary(["a", "b"])
        #expect(result.shown == ["a", "b"])
        #expect(result.hiddenCount == 0)
        #expect(result.hiddenText == nil)
    }

    @Test func 세_개_이상이면_앞의_두_개만_보이고_나머지는_외_N개로_접는다() {
        let result = summary(["a", "b", "c", "d", "e"])
        #expect(result.shown == ["a", "b"])
        #expect(result.hiddenText == "외 3개")
    }

    @Test func 메모_없는_북마크는_세지_않는다() {
        let result = summary(["", "a", "  \n", "b", "c"])
        #expect(result.shown == ["a", "b"])
        #expect(result.hiddenText == "외 1개")
    }
}
