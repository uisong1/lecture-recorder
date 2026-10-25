#if canImport(SwiftData)
import Foundation
import SwiftData
import Testing
@testable import LectureCore

@MainActor
@Suite struct RecordingLibraryTests {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    init() throws {
        container = try LectureModelContainer.make(inMemory: true)
    }

    @discardableResult
    func addRecording(_ title: String, subject: Subject?, at startedAt: Date) -> Recording {
        let recording = Recording(title: title, subject: subject, startedAt: startedAt, duration: 60, relativePath: "\(title).m4a")
        context.insert(recording)
        return recording
    }

    @Test func 과목을_고르면_그_과목의_녹음이_최신순으로_나온다() throws {
        let subjects = SubjectManager(context: context)
        let ds = try subjects.add(name: "자료구조", color: .green)
        let os = try subjects.add(name: "운영체제", color: .blue)
        addRecording("월요일", subject: ds, at: date(2026, 3, 2, 10, 0))
        addRecording("수요일", subject: ds, at: date(2026, 3, 4, 10, 0))
        addRecording("운영체제", subject: os, at: date(2026, 3, 3, 13, 0))
        try context.save()

        let library = RecordingLibrary(context: context)
        library.select(.subject(ds.persistentModelID))

        #expect(library.recordings.map(\.title) == ["수요일", "월요일"])
    }

    @Test func 미분류를_고르면_과목_없는_녹음만_나온다() throws {
        let ds = try SubjectManager(context: context).add(name: "자료구조", color: .green)
        addRecording("과목 있음", subject: ds, at: date(2026, 3, 2, 10, 0))
        addRecording("과목 없음", subject: nil, at: date(2026, 3, 2, 12, 30))
        try context.save()

        let library = RecordingLibrary(context: context)
        library.select(.unclassified)

        #expect(library.recordings.map(\.title) == ["과목 없음"])
    }

    @Test func 아무것도_고르지_않으면_목록이_비어_있다() throws {
        addRecording("a", subject: nil, at: date(2026, 3, 2, 10, 0))
        try context.save()
        #expect(RecordingLibrary(context: context).recordings.isEmpty)
    }

    @Test func 새_녹음이_저장된_뒤_다시_읽으면_목록에_나타난다() throws {
        let library = RecordingLibrary(context: context)
        library.select(.unclassified)
        #expect(library.recordings.isEmpty)

        addRecording("새 녹음", subject: nil, at: date(2026, 3, 2, 10, 0))
        try context.save()
        library.reload()

        #expect(library.recordings.map(\.title) == ["새 녹음"])
    }

    @Test func 분류별_녹음_수를_센다() throws {
        let ds = try SubjectManager(context: context).add(name: "자료구조", color: .green)
        addRecording("a", subject: ds, at: date(2026, 3, 2, 10, 0))
        addRecording("b", subject: ds, at: date(2026, 3, 3, 10, 0))
        addRecording("c", subject: nil, at: date(2026, 3, 4, 10, 0))
        try context.save()

        let library = RecordingLibrary(context: context)
        #expect(library.count(for: .subject(ds.persistentModelID)) == 2)
        #expect(library.count(for: .unclassified) == 1)
    }

    @Test func 고르고_있던_과목이_삭제되면_선택이_풀린다() throws {
        let subjects = SubjectManager(context: context)
        let ds = try subjects.add(name: "자료구조", color: .green)
        let library = RecordingLibrary(context: context)
        library.select(.subject(ds.persistentModelID))

        try subjects.delete(ds)
        library.reload()

        #expect(library.selection == nil)
        #expect(library.subjects.isEmpty)
    }
}
#endif
