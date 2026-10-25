#if canImport(SwiftData)
import Foundation
import SwiftData
import Testing
@testable import LectureCore

@MainActor
@Suite struct TimetableImporterTests {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }
    let importer: TimetableImporter

    init() throws {
        container = try LectureModelContainer.make(inMemory: true)
        importer = TimetableImporter(context: container.mainContext)
    }

    /// 에브리타임 사진에서 읽은 초안. 시간 없는 과목 하나가 들어 있다.
    func fixtureEditor() throws -> TimetableDraftEditor {
        let columns = try TimetableReader.columns(from: EverytimeFixture.all)
        let draft = try TimetableReader.read(
            observations: EverytimeFixture.all,
            columns: columns,
            strips: EverytimeFixture.strips(for: columns),
            lineRows: EverytimeFixture.lineRows
        )
        return TimetableDraftEditor(draft: draft)
    }

    func allSubjects() throws -> [Subject] {
        try context.fetch(FetchDescriptor<Subject>(sortBy: [SortDescriptor(\.name)]))
    }

    func allSlots() throws -> [TimeSlot] {
        try context.fetch(FetchDescriptor<TimeSlot>())
    }

    @Test func 사진의_시간표를_가져오면_과목과_칸이_만들어진다() throws {
        let result = try importer.apply(fixtureEditor())
        let subjects = try allSubjects()
        let slots = try allSlots()

        #expect(result.semester == "2026년 2학기")
        #expect(result.slotCount == 10)
        #expect(result.removedSlotCount == 0)
        #expect(result.createdSubjects.count == 7)
        #expect(result.reusedSubjects.isEmpty)
        #expect(slots.count == 10)
        #expect(subjects.map(\.name).sorted() == ["AI기술산업응용및설계(숭실사이버대)", "AI데이터분석및실습", "글로벌시민의식", "사용자인터페이스", "알고리즘", "컴퓨터구조", "컴퓨터네트워크"].sorted())
        #expect(subjects.allSatisfy { $0.semester == "2026년 2학기" })
    }

    @Test func 요일마다_나오는_같은_이름은_한_과목이다() throws {
        try importer.apply(fixtureEditor())
        let subjects = try allSubjects()
        let architecture = try #require(subjects.first { $0.name == "컴퓨터구조" })
        #expect(architecture.timeSlots.count == 2)
        #expect(architecture.timeSlots.compactMap { $0.period?.weekday }.sorted() == [.wednesday, .friday])
    }

    @Test func 시간_없는_과목은_칸_없이_만든다() throws {
        try importer.apply(fixtureEditor())
        let subjects = try allSubjects()
        let cyber = try #require(subjects.first { $0.name.hasPrefix("AI기술산업") })
        #expect(cyber.timeSlots.isEmpty)
    }

    @Test func 제외한_줄은_과목도_칸도_만들지_않는다() throws {
        try importer.apply(fixtureEditor())
        let names = try allSubjects().map(\.name)
        #expect(!names.contains("탐테"))
        #expect(!names.contains("복지일"))
        #expect(!names.contains("비전채플"))
    }

    @Test func 줄을_켜면_그_과목도_만든다() throws {
        var editor = try fixtureEditor()
        let chapel = try #require(editor.draft.rows.firstIndex { $0.name == "비전채플" })
        editor.setInclude(true, at: chapel)
        let result = try importer.apply(editor)
        #expect(result.slotCount == 11)
        #expect(try allSubjects().map(\.name).contains("비전채플"))
    }

    @Test func 기존_시간표_칸은_지우고_과목과_녹음은_남긴다() throws {
        let old = Subject(name: "옛 과목", color: .red)
        context.insert(old)
        context.insert(try TimeSlot(weekday: .tuesday, start: TimeOfDay(hour: 10, minute: 30), end: TimeOfDay(hour: 11, minute: 45), subject: old))
        let recording = Recording(title: "녹음", subject: old, startedAt: date(2026, 3, 3, 10, 30), duration: 60, relativePath: "옛 과목/a.m4a")
        context.insert(recording)
        try context.save()

        let result = try importer.apply(fixtureEditor())

        #expect(result.removedSlotCount == 1)
        #expect(try allSlots().count == 10)
        #expect(try allSubjects().map(\.name).contains("옛 과목"))
        #expect(old.timeSlots.isEmpty)
        #expect(recording.subject === old)
        #expect(try context.fetch(FetchDescriptor<Recording>()).count == 1)
    }

    @Test func 이름이_같은_기존_과목은_다시_쓰고_학기를_바꾼다() throws {
        let existing = Subject(name: "알고리즘", color: .teal)
        existing.semester = "2026년 1학기"
        context.insert(existing)
        try context.save()

        let result = try importer.apply(fixtureEditor())

        #expect(result.reusedSubjects == ["알고리즘"])
        #expect(!result.createdSubjects.contains("알고리즘"))
        #expect(try allSubjects().filter { $0.name == "알고리즘" }.count == 1)
        #expect(existing.semester == "2026년 2학기")
        #expect(existing.timeSlots.count == 2)
        #expect(existing.color == .teal)
    }

    @Test func 새_학기로_바꿔도_지난_학기_녹음은_그대로_남는다() throws {
        let kept = Subject(name: "지난학기만듣던과목", color: .red)
        kept.semester = "2026년 1학기"
        let shared = Subject(name: "알고리즘", color: .teal)
        shared.semester = "2026년 1학기"
        context.insert(kept)
        context.insert(shared)
        let keptRecording = Recording(title: "a", subject: kept, startedAt: date(2026, 4, 6, 10, 0), duration: 60, relativePath: "2026년 1학기/지난학기만듣던과목/04-06 월 10-00.m4a")
        let sharedRecording = Recording(title: "b", subject: shared, startedAt: date(2026, 4, 7, 14, 0), duration: 60, relativePath: "2026년 1학기/알고리즘/04-07 화 14-00.m4a")
        let unclassified = Recording(title: "c", subject: nil, startedAt: date(2026, 4, 8, 9, 0), duration: 60, relativePath: "미분류/04-08 수 09-00.m4a")
        context.insert(keptRecording)
        context.insert(sharedRecording)
        context.insert(unclassified)
        try context.save()

        try importer.apply(fixtureEditor())

        let recordings = try context.fetch(FetchDescriptor<Recording>())
        #expect(recordings.count == 3)
        // 새 시간표에 없는 과목은 학기도 녹음도 건드리지 않는다.
        #expect(kept.semester == "2026년 1학기")
        #expect(keptRecording.subject === kept)
        #expect(keptRecording.relativePath == "2026년 1학기/지난학기만듣던과목/04-06 월 10-00.m4a")
        // 다시 쓰는 과목은 학기만 바뀌고 녹음 파일 경로와 연결은 그대로다.
        #expect(sharedRecording.subject === shared)
        #expect(sharedRecording.relativePath == "2026년 1학기/알고리즘/04-07 화 14-00.m4a")
        #expect(unclassified.subject == nil)
        #expect(unclassified.relativePath == "미분류/04-08 수 09-00.m4a")
    }

    @Test func 시간표를_가져와도_과목의_옛_시간표_칸만_바뀐다() throws {
        let kept = Subject(name: "지난학기만듣던과목", color: .red)
        context.insert(kept)
        context.insert(try TimeSlot(weekday: .monday, start: TimeOfDay(hour: 9), end: TimeOfDay(hour: 10), subject: kept))
        try context.save()

        try importer.apply(fixtureEditor())

        #expect(kept.timeSlots.isEmpty)
        #expect(try allSubjects().contains { $0 === kept })
    }

    @Test func 대소문자가_달라도_같은_과목으로_본다() throws {
        context.insert(Subject(name: "ai데이터분석및실습", color: .blue))
        try context.save()
        let result = try importer.apply(fixtureEditor())
        #expect(result.reusedSubjects == ["ai데이터분석및실습"])
        #expect(try allSubjects().filter { $0.name.lowercased() == "ai데이터분석및실습" }.count == 1)
    }

    @Test func 같은_초안을_다시_가져와도_늘어나지_않는다() throws {
        try importer.apply(fixtureEditor())
        let result = try importer.apply(fixtureEditor())
        #expect(result.createdSubjects.isEmpty)
        #expect(result.removedSlotCount == 10)
        #expect(try allSubjects().count == 7)
        #expect(try allSlots().count == 10)
    }

    @Test func 고쳐야_할_문제가_있으면_아무것도_저장하지_않는다() throws {
        let old = Subject(name: "옛 과목", color: .red)
        context.insert(old)
        context.insert(try TimeSlot(weekday: .monday, start: TimeOfDay(hour: 9), end: TimeOfDay(hour: 10), subject: old))
        try context.save()

        var editor = try fixtureEditor()
        editor.setName("", at: 0)
        #expect(throws: TimetableImportError.invalid([.emptyName(row: 0)])) { try importer.apply(editor) }

        #expect(try allSlots().count == 1)
        #expect(try allSubjects().map(\.name) == ["옛 과목"])
    }

    @Test func 학기_이름이_없으면_가져오지_않는다() throws {
        var editor = try fixtureEditor()
        editor.setSemester("")
        #expect(throws: TimetableImportError.invalid([.emptySemester])) { try importer.apply(editor) }
        #expect(try allSlots().isEmpty)
    }

    @Test func 가져온_뒤_시간표로_수업을_분류한다() throws {
        try importer.apply(fixtureEditor())
        let schedule = ScheduleManager(context: context)
        let classification = schedule.schedule().classify(at: date(2026, 3, 3, 14, 0), calendar: seoulCalendar)
        let subjects = try allSubjects()
        let algorithms = try #require(subjects.first { $0.name == "알고리즘" })
        #expect(classification == .subject(algorithms.persistentModelID))
    }

    @Test func 지울_기존_칸_수를_미리_알려_준다() throws {
        #expect(importer.existingSlotCount() == 0)
        try importer.apply(fixtureEditor())
        #expect(importer.existingSlotCount() == 10)
    }

    @Test func 새_과목에는_색을_돌려_가며_정한다() throws {
        try importer.apply(fixtureEditor())
        let colors = Set(try allSubjects().map(\.color))
        #expect(colors.count > 1)
        #expect(!colors.contains(.gray))
    }
}
#endif
