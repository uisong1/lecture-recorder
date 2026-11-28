import Testing
@testable import LectureCore

@Suite struct TranscriptExpansionTests {
    @Test func 처음엔_아무_줄도_펼치지_않는다() {
        let expansion = TranscriptExpansion<Int>()
        #expect(expansion.expanded == nil)
        #expect(!expansion.isExpanded(1))
    }

    @Test func 누르면_펼치고_다시_누르면_접는다() {
        var expansion = TranscriptExpansion<Int>()
        expansion.toggle(1)
        #expect(expansion.isExpanded(1))
        expansion.toggle(1)
        #expect(expansion.expanded == nil)
    }

    @Test func 다른_줄을_누르면_앞의_줄은_접힌다() {
        var expansion = TranscriptExpansion<Int>()
        expansion.toggle(1)
        expansion.toggle(2)
        #expect(!expansion.isExpanded(1))
        #expect(expansion.isExpanded(2))
    }

    @Test func 목록에서_사라진_줄은_접는다() {
        var expansion = TranscriptExpansion(expanded: 3)
        expansion.keepOnly([1, 2, 3])
        #expect(expansion.isExpanded(3))
        expansion.keepOnly([1, 2])
        #expect(expansion.expanded == nil)
    }
}
