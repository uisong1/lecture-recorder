import Testing
@testable import LectureCore

@Suite struct SubjectColorTests {
    @Test func 색은_11가지이고_이름이_모두_다르다() {
        #expect(SubjectColor.allCases.count == 11)
        let names = SubjectColor.allCases.map(\.displayName)
        #expect(Set(names).count == names.count)
        #expect(names.allSatisfy { !$0.isEmpty })
    }

    @Test func 원시값으로_다시_만들_수_있다() {
        for color in SubjectColor.allCases {
            #expect(SubjectColor(rawValue: color.rawValue) == color)
        }
    }

    @Test func 과목은_알_수_없는_저장값이면_회색으로_본다() {
        let subject = Subject(name: "자료구조", color: .red)
        #expect(subject.color == .red)
        subject.colorRawValue = "없는색"
        #expect(subject.color == .gray)
    }

    @Test func 과목_색을_바꾸면_저장값도_바뀐다() {
        let subject = Subject(name: "자료구조")
        #expect(subject.color == .blue)
        subject.color = .teal
        #expect(subject.colorRawValue == "teal")
    }
}
