import Foundation
import Testing
@testable import LectureCore

@Suite struct TimetableWordGroupingTests {
    func word(_ text: String, _ x: Double, _ width: Double, y: Double = 100, height: Double = 30) -> TextObservation {
        TextObservation(text: text, x: x, y: y, width: width, height: height)
    }

    @Test func 가까운_낱말은_한_덩어리로_이어_붙인다() {
        let merged = TimetableWordGrouping.merge([word("정보과학관", 308, 130), word("212", 450, 45)])
        #expect(merged == [TextObservation(text: "정보과학관 212", x: 308, y: 100, width: 187, height: 30)])
    }

    @Test func 멀리_떨어진_낱말은_따로_둔다() {
        // 화요일 칸의 "컴퓨터구조"와 수요일 칸의 "알고리즘": 칸 사이 간격이 글자 높이의 두 배.
        let merged = TimetableWordGrouping.merge([word("컴퓨터구조", 521, 152), word("알고리즘", 734, 121)])
        #expect(merged.map(\.text) == ["컴퓨터구조", "알고리즘"])
    }

    @Test func 요일_머리글은_한_글자씩_나뉜다() {
        let merged = TimetableWordGrouping.merge([
            word("월", 180, 22), word("화", 393, 24), word("수", 606, 24), word("목", 819, 24), word("금", 1032, 24),
        ])
        #expect(merged.map(\.text) == ["월", "화", "수", "목", "금"])
    }

    @Test func 순서가_섞여_있어도_왼쪽부터_이어_붙인다() {
        let merged = TimetableWordGrouping.merge([word("212", 450, 45), word("정보과학관", 308, 130)])
        #expect(merged.map(\.text) == ["정보과학관 212"])
    }

    @Test func 낱말이_없으면_빈_목록() {
        #expect(TimetableWordGrouping.merge([]).isEmpty)
    }

    @Test func 공백으로_낱말_범위를_나눈다() {
        let text = "  정보과학관  212 (실습실) "
        let words = TimetableWordGrouping.wordRanges(in: text).map { String(text[$0]) }
        #expect(words == ["정보과학관", "212", "(실습실)"])
        #expect(TimetableWordGrouping.wordRanges(in: "").isEmpty)
        #expect(TimetableWordGrouping.wordRanges(in: "   ").isEmpty)
        #expect(TimetableWordGrouping.wordRanges(in: "월").count == 1)
    }
}
