import Foundation
import Testing
@testable import LectureCore

@Suite struct TimetableDraftEditorTests {
    func hm(_ hour: Int, _ minute: Int = 0) -> TimeOfDay {
        guard let time = try? TimeOfDay(hour: hour, minute: minute) else { fatalError("잘못된 테스트 시각") }
        return time
    }

    func row(_ name: String, _ weekday: Weekday, _ start: TimeOfDay, _ end: TimeOfDay, include: Bool = true) -> TimetableRow {
        TimetableRow(name: name, weekday: weekday, start: start, end: end, hasRoom: true, include: include)
    }

    func make(_ rows: [TimetableRow] = [], semester: String? = "2026년 2학기", untimed: [String] = []) -> TimetableDraftEditor {
        TimetableDraftEditor(draft: TimetableDraft(semester: semester, rows: rows, untimedSubjects: untimed))
    }

    func readFixtureEditor() throws -> TimetableDraftEditor {
        let columns = try TimetableReader.columns(from: EverytimeFixture.all)
        let draft = try TimetableReader.read(
            observations: EverytimeFixture.all,
            columns: columns,
            strips: EverytimeFixture.strips(for: columns),
            lineRows: EverytimeFixture.lineRows
        )
        return TimetableDraftEditor(draft: draft)
    }

    // MARK: 검사

    @Test func 사진에서_읽은_초안은_그대로_저장할_수_있다() throws {
        let editor = try readFixtureEditor()
        #expect(editor.isValid)
        #expect(editor.includedRows.count == 10)
    }

    @Test func 이름이_비면_문제다() {
        let editor = make([row("  ", .monday, hm(9), hm(10))])
        #expect(editor.issues == [.emptyName(row: 0)])
    }

    @Test func 미분류는_과목_이름으로_쓸_수_없다() {
        #expect(make([row("미분류", .monday, hm(9), hm(10))]).issues == [.reservedName(row: 0)])
    }

    @Test func 끝이_시작과_같거나_빠르면_문제다() {
        #expect(make([row("가", .monday, hm(9), hm(9))]).issues == [.timeOrder(row: 0)])
        #expect(make([row("가", .monday, hm(10), hm(9))]).issues == [.timeOrder(row: 0)])
    }

    @Test func 같은_요일에_시간이_겹치면_뒷줄의_문제다() {
        let rows = [row("가", .monday, hm(9), hm(10, 15)), row("나", .monday, hm(10), hm(11))]
        #expect(make(rows).issues == [.overlap(row: 1, with: 0)])
    }

    @Test func 끝나는_시각에_시작하는_칸은_겹치지_않는다() {
        let rows = [row("가", .monday, hm(9), hm(10)), row("나", .monday, hm(10), hm(11))]
        #expect(make(rows).isValid)
    }

    @Test func 다른_요일의_같은_시간은_겹치지_않는다() {
        let rows = [row("가", .monday, hm(9), hm(10)), row("나", .tuesday, hm(9), hm(10))]
        #expect(make(rows).isValid)
    }

    @Test func 같은_과목이라도_시간이_겹치면_문제다() {
        let rows = [row("가", .monday, hm(9), hm(10)), row("가", .monday, hm(9, 30), hm(10, 30))]
        #expect(make(rows).issues == [.overlap(row: 1, with: 0)])
    }

    @Test func 저장_대상이_아닌_줄의_문제는_세지_않는다() {
        let rows = [
            row("가", .monday, hm(9), hm(10)),
            row("", .monday, hm(9, 30), hm(10, 30), include: false),
            row("나", .monday, hm(9, 30), hm(9), include: false),
        ]
        #expect(make(rows).isValid)
    }

    @Test func 겹치는_줄을_제외하면_문제가_사라진다() {
        var editor = make([row("가", .monday, hm(9), hm(10)), row("나", .monday, hm(9, 30), hm(11))])
        #expect(!editor.isValid)
        editor.setInclude(false, at: 1)
        #expect(editor.isValid)
    }

    @Test func 학기_이름이_없으면_문제다() {
        #expect(make(semester: nil).issues == [.emptySemester])
        #expect(make(semester: "   ").issues == [.emptySemester])
        var fixed = make(semester: nil)
        fixed.setSemester(" 2026년 1학기 ")
        #expect(fixed.isValid)
        #expect(fixed.semesterName == "2026년 1학기")
    }

    @Test func 문제_문구는_줄_번호를_1부터_센다() {
        #expect(TimetableDraftEditor.Issue.emptyName(row: 0).message == "1번째 줄의 과목 이름이 비어 있습니다.")
        #expect(TimetableDraftEditor.Issue.overlap(row: 2, with: 0).message == "1번째 줄과 3번째 줄의 시간이 겹칩니다.")
        #expect(TimetableDraftEditor.Issue.timeOrder(row: 1).message == "2번째 줄: 끝나는 시각은 시작 시각보다 늦어야 합니다.")
        #expect(TimetableDraftEditor.Issue.emptySemester.message == "학기 이름을 입력하세요.")
    }

    // MARK: 고치기

    @Test func 과목명_요일_시간을_고친다() {
        var editor = make([row("알고리듬", .monday, hm(9), hm(10))])
        editor.setName("알고리즘", at: 0)
        editor.setWeekday(.thursday, at: 0)
        editor.setStart(hm(13, 30), at: 0)
        editor.setEnd(hm(14, 45), at: 0)
        #expect(editor.draft.rows == [row("알고리즘", .thursday, hm(13, 30), hm(14, 45))])
    }

    @Test func 줄을_더하고_지운다() {
        var editor = make([row("가", .monday, hm(9), hm(10))])
        let index = editor.addRow()
        #expect(index == 1)
        #expect(editor.draft.rows[1].include)
        #expect(editor.draft.rows[1].name.isEmpty)
        #expect(editor.issues == [.emptyName(row: 1), .overlap(row: 1, with: 0)])
        editor.deleteRow(at: 0)
        #expect(editor.draft.rows.count == 1)
        #expect(editor.issues == [.emptyName(row: 0)])
    }

    @Test func 범위_밖_위치는_무시한다() {
        var editor = make([row("가", .monday, hm(9), hm(10))])
        let before = editor
        editor.setName("나", at: 5)
        editor.setWeekday(.friday, at: -1)
        editor.setStart(hm(1), at: 1)
        editor.setEnd(hm(2), at: 9)
        editor.setInclude(false, at: 3)
        editor.deleteRow(at: 4)
        editor.renameUntimedSubject(at: 0, to: "다")
        editor.removeUntimedSubject(at: 0)
        #expect(editor == before)
    }

    @Test func 시간_없는_과목을_더하고_고치고_지운다() {
        var editor = make(untimed: ["사이버 강의"])
        editor.addUntimedSubject("글쓰기")
        editor.renameUntimedSubject(at: 0, to: "사이버강의")
        #expect(editor.draft.untimedSubjects == ["사이버강의", "글쓰기"])
        editor.removeUntimedSubject(at: 1)
        #expect(editor.draft.untimedSubjects == ["사이버강의"])
    }

    @Test func 시간_없는_과목은_빈_이름과_중복을_뺀다() {
        let editor = make(untimed: ["  ", "AI 설계", "ai 설계", "미분류", "글쓰기 "])
        #expect(editor.cleanedUntimedSubjects == ["AI 설계", "글쓰기"])
    }
}
