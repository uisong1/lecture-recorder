#if canImport(SwiftData)
import Foundation
import SwiftData
import Testing
@testable import LectureCore

struct FakeTimetableReader: TimetableImageReading {
    var result: Result<TimetableDraft, any Error>

    func readTimetable(from imageData: Data) async throws -> TimetableDraft {
        try result.get()
    }
}

@MainActor
final class ImportedCounter {
    var count = 0
}

@MainActor
@Suite struct TimetableImportModelTests {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }
    let counter = ImportedCounter()

    init() throws {
        container = try LectureModelContainer.make(inMemory: true)
    }

    func fixtureDraft() throws -> TimetableDraft {
        let columns = try TimetableReader.columns(from: EverytimeFixture.all)
        return try TimetableReader.read(
            observations: EverytimeFixture.all,
            columns: columns,
            strips: EverytimeFixture.strips(for: columns),
            lineRows: EverytimeFixture.lineRows
        )
    }

    func makeModel(_ result: Result<TimetableDraft, any Error>) -> TimetableImportModel {
        let counter = counter
        return TimetableImportModel(
            reader: FakeTimetableReader(result: result),
            importer: TimetableImporter(context: context),
            onImported: { counter.count += 1 }
        )
    }

    func slotCount() throws -> Int { try context.fetchCount(FetchDescriptor<TimeSlot>()) }

    @Test func 이미지를_읽으면_미리보기가_나온다() async throws {
        let model = makeModel(.success(try fixtureDraft()))

        await model.load(imageData: Data([1]))

        #expect(model.phase == .preview)
        #expect(model.editor?.draft.semester == "2026년 2학기")
        #expect(model.editor?.draft.rows.count == 14)
        #expect(model.errorMessage == nil)
        // 미리보기까지는 아무것도 저장하지 않는다.
        #expect(try slotCount() == 0)
    }

    @Test func 지워질_기존_시간표_칸_수를_알려_준다() async throws {
        let subject = Subject(name: "옛 과목")
        context.insert(subject)
        context.insert(TimeSlot(try ClassPeriod(weekday: .monday, start: TimeOfDay(hour: 9), end: TimeOfDay(hour: 10)), subject: subject))
        try context.save()
        let model = makeModel(.success(try fixtureDraft()))

        await model.load(imageData: Data([1]))

        #expect(model.existingSlotCount == 1)
    }

    @Test func 읽지_못하면_이유를_알리고_처음으로_돌아간다() async throws {
        let model = makeModel(.failure(TimetableReadError.noGrid))

        await model.load(imageData: Data([1]))

        #expect(model.phase == .waiting)
        #expect(model.editor == nil)
        #expect(model.errorMessage == TimetableReadError.noGrid.errorDescription)
    }

    @Test func 알_수_없는_오류도_알린다() async throws {
        let model = makeModel(.failure(CocoaError(.fileReadCorruptFile)))

        await model.load(imageData: Data([1]))

        #expect(model.phase == .waiting)
        #expect(model.errorMessage?.hasPrefix("이미지를 읽지 못했습니다") == true)
    }

    @Test func 칸이_하나도_없으면_가져오지_않는다() async throws {
        let model = makeModel(.success(TimetableDraft(semester: "2026년 2학기", rows: [], untimedSubjects: [])))

        await model.load(imageData: Data([1]))

        #expect(model.phase == .waiting)
        #expect(model.errorMessage?.hasPrefix("시간표 칸을 찾지 못했습니다") == true)
    }

    @Test func 파일을_열지_못하면_알린다() async throws {
        let model = makeModel(.success(try fixtureDraft()))

        await model.load(fileAt: URL(filePath: "/tmp/LectureRecorderTests/없는-이미지.png"))

        #expect(model.phase == .waiting)
        #expect(model.errorMessage?.hasPrefix("이미지 파일을 열지 못했습니다") == true)
    }

    @Test func 확인하면_저장하고_후속_작업을_부른다() async throws {
        let model = makeModel(.success(try fixtureDraft()))
        await model.load(imageData: Data([1]))

        await model.confirm()

        guard case .saved(let result) = model.phase else {
            Issue.record("저장 상태가 아님: \(model.phase)")
            return
        }
        #expect(result.slotCount == 10)
        #expect(result.createdSubjects.count == 7)
        #expect(try slotCount() == 10)
        #expect(model.editor == nil)
        #expect(counter.count == 1)
    }

    @Test func 미리보기에서_고친_내용이_저장된다() async throws {
        let model = makeModel(.success(try fixtureDraft()))
        await model.load(imageData: Data([1]))
        // 첫 줄을 끄면 그 칸은 저장되지 않는다.
        model.editor?.setInclude(false, at: 0)
        let included = model.editor?.includedRows.count

        await model.confirm()

        guard case .saved(let result) = model.phase else {
            Issue.record("저장 상태가 아님: \(model.phase)")
            return
        }
        #expect(result.slotCount == included)
    }

    @Test func 고칠_곳이_남아_있으면_저장하지_않고_미리보기에_남는다() async throws {
        let model = makeModel(.success(try fixtureDraft()))
        await model.load(imageData: Data([1]))
        model.editor?.setSemester("")

        await model.confirm()

        #expect(model.phase == .preview)
        #expect(model.errorMessage == TimetableDraftEditor.Issue.emptySemester.message)
        #expect(try slotCount() == 0)
        #expect(counter.count == 0)
    }

    @Test func 다시_고르면_초안을_버리고_처음으로_돌아간다() async throws {
        let model = makeModel(.success(try fixtureDraft()))
        await model.load(imageData: Data([1]))

        model.reset()

        #expect(model.phase == .waiting)
        #expect(model.editor == nil)
        #expect(try slotCount() == 0)
    }

    @Test func 저장한_뒤에는_다시_확인해도_두_번_저장하지_않는다() async throws {
        let model = makeModel(.success(try fixtureDraft()))
        await model.load(imageData: Data([1]))
        await model.confirm()

        await model.confirm()

        #expect(counter.count == 1)
        #expect(try slotCount() == 10)
    }
}
#endif
