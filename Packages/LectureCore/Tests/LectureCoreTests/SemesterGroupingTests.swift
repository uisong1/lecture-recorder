import Foundation
import Testing
@testable import LectureCore

@Suite struct SemesterGroupingTests {
    func input(_ name: String, _ semester: String, scheduled: Bool = true) -> SemesterGrouping.Input {
        SemesterGrouping.Input(name: name, semester: semester, hasSchedule: scheduled)
    }

    @Test func 과목이_없으면_묶음도_없다() {
        #expect(SemesterGrouping.sections(for: []).isEmpty)
    }

    @Test func 학기가_하나면_한_묶음이고_현재_학기다() {
        let sections = SemesterGrouping.sections(for: [input("자료구조", "2026년 2학기"), input("운영체제", "2026년 2학기")])
        #expect(sections == [.init(semester: "2026년 2학기", indices: [0, 1], isCurrent: true)])
    }

    @Test func 학기가_여럿이면_최신이_위다() {
        let sections = SemesterGrouping.sections(for: [
            input("a", "2025년 2학기"), input("b", "2026년 1학기"), input("c", "2026년 2학기"), input("d", "2025년 1학기"),
        ])
        #expect(sections.map(\.semester) == ["2026년 2학기", "2026년 1학기", "2025년 2학기", "2025년 1학기"])
        #expect(sections.map(\.indices) == [[2], [1], [0], [3]])
        #expect(sections.map(\.isCurrent) == [true, false, false, false])
    }

    @Test func 학기_이름의_연도와_학기_숫자로_정렬한다() {
        let names = ["2025년 2학기", "2026년 1학기", "2026년 2학기", "2026년 여름학기", "이름만"]
        let sections = SemesterGrouping.sections(for: names.map { input($0, $0) })
        // 숫자를 못 읽는 이름은 뒤로 가고, 학기 숫자가 없는 학기는 같은 해의 숫자 있는 학기보다 뒤다.
        #expect(sections.map(\.semester) == ["2026년 2학기", "2026년 1학기", "2026년 여름학기", "2025년 2학기", "이름만"])
    }

    @Test func 학기가_없는_과목은_기타로_맨_아래에_모인다() {
        let sections = SemesterGrouping.sections(for: [input("직접 만듦", ""), input("a", "2026년 1학기"), input("공백", "  ")])
        #expect(sections.map(\.title) == ["2026년 1학기", "기타"])
        #expect(sections.last?.indices == [0, 2])
        #expect(sections.last?.isCurrent == false)
    }

    @Test func 학기가_없는_과목만_있으면_현재_학기가_없다() {
        let sections = SemesterGrouping.sections(for: [input("a", ""), input("b", "")])
        #expect(sections.count == 1)
        #expect(sections.allSatisfy { !$0.isCurrent })
        #expect(!SemesterGrouping.showsHeaders(sections))
    }

    @Test func 현재_학기는_시간표_칸이_있는_과목의_학기다() {
        // 가장 최근 학기(2026년 2학기)의 과목이 시간표가 없으면, 시간표가 있는 학기가 현재다.
        let sections = SemesterGrouping.sections(for: [
            input("지난", "2026년 1학기", scheduled: true), input("새로 만듦", "2026년 2학기", scheduled: false),
        ])
        #expect(sections.map(\.semester) == ["2026년 2학기", "2026년 1학기"])
        #expect(sections.map(\.isCurrent) == [false, true])
    }

    @Test func 시간표_있는_학기가_여럿이면_그중_최근이_현재다() {
        let sections = SemesterGrouping.sections(for: [input("a", "2025년 2학기"), input("b", "2026년 1학기")])
        #expect(sections.first?.isCurrent == true)
    }

    @Test func 시간표_있는_과목이_없으면_가장_최근_학기가_현재다() {
        let sections = SemesterGrouping.sections(for: [input("a", "2025년 2학기", scheduled: false), input("b", "2026년 1학기", scheduled: false)])
        #expect(sections.map(\.isCurrent) == [true, false])
    }

    @Test func 학기가_정해진_과목이_있으면_제목을_보인다() {
        #expect(SemesterGrouping.showsHeaders(SemesterGrouping.sections(for: [input("a", "2026년 1학기"), input("b", "")])))
    }

    // MARK: 펼침 상태

    @Test func 기본은_현재_학기와_기타만_펼쳐져_있다() {
        let sections = SemesterGrouping.sections(for: [input("a", "2026년 2학기"), input("b", "2025년 2학기"), input("c", "")])
        let expansion = SemesterExpansion()
        #expect(sections.map { expansion.isExpanded($0) } == [true, false, true])
    }

    @Test func 사용자가_바꾼_펼침은_현재_학기가_바뀌어도_유지된다() {
        var sections = SemesterGrouping.sections(for: [input("a", "2026년 1학기"), input("b", "2025년 2학기")])
        var expansion = SemesterExpansion()
        expansion.set(true, for: sections[1])
        expansion.set(false, for: sections[0])

        // 새 학기가 생겨 현재가 바뀐다.
        sections = SemesterGrouping.sections(for: [input("a", "2026년 1학기"), input("b", "2025년 2학기"), input("c", "2026년 2학기")])
        #expect(sections.map(\.semester) == ["2026년 2학기", "2026년 1학기", "2025년 2학기"])
        #expect(sections.map { expansion.isExpanded($0) } == [true, false, true])
    }

    @Test func 펼침_상태를_문자열로_저장하고_복원한다() {
        let sections = SemesterGrouping.sections(for: [input("a", "2026년 1학기"), input("b", "2025년 2학기")])
        var expansion = SemesterExpansion()
        expansion.set(true, for: sections[1])

        let restored = SemesterExpansion(json: expansion.json)

        #expect(restored == expansion)
        #expect(restored.isExpanded(sections[1]))
    }

    @Test func 저장된_문자열이_비었거나_깨졌으면_기본_상태다() {
        #expect(SemesterExpansion(json: "") == SemesterExpansion())
        #expect(SemesterExpansion(json: "not json") == SemesterExpansion())
    }
}
