import Testing
@testable import LectureCore

@Suite struct UnplayedBadgeTests {
    @Test func 안_들은_녹음이_있으면_점을_보이고_0이면_숨긴다() {
        #expect(UnplayedBadge.showsDot(count: 3))
        #expect(UnplayedBadge.showsDot(count: 1))
        #expect(!UnplayedBadge.showsDot(count: 0))
    }

    @Test func 접근성_라벨은_과목_이름과_개수를_읽는다() {
        #expect(UnplayedBadge.accessibilityLabel(name: "자료구조", count: 3) == "자료구조, 안 들은 녹음 3개")
        #expect(UnplayedBadge.accessibilityLabel(name: "자료구조", count: 0) == "자료구조")
    }
}
