#if canImport(SwiftData)
import Foundation
import SwiftData
import Testing
@testable import LectureCore

@MainActor
@Suite struct RecordingLibraryTests {
    let container: ModelContainer
    let context: ModelContext
    let ds: Subject
    let os: Subject

    init() throws {
        container = try LectureModelContainer.make(inMemory: true)
        context = container.mainContext
        ds = Subject(name: "자료구조")
        os = Subject(name: "운영체제")
        context.insert(ds)
        context.insert(os)
        // 저장 전의 임시 ID는 저장하면 바뀌므로 먼저 저장한다.
        try context.save()
    }

    private func add(_ title: String, _ subject: Subject?, at seconds: TimeInterval) {
        context.insert(Recording(title: title, subject: subject, startedAt: Date(timeIntervalSince1970: seconds), duration: 60, relativePath: "\(title).m4a"))
    }

    @Test func 고른_과목의_녹음만_최신순으로_나온다() throws {
        add("월", ds, at: 100)
        add("수", ds, at: 300)
        add("화", os, at: 200)
        try context.save()

        let library = RecordingLibrary(context: context)
        library.select(.subject(ds.persistentModelID))
        #expect(library.recordings.map(\.title) == ["수", "월"])
        library.select(.subject(os.persistentModelID))
        #expect(library.recordings.map(\.title) == ["화"])
    }

    @Test func 미분류는_과목_없는_녹음만_보여준다() throws {
        add("과목", ds, at: 100)
        add("미분류1", nil, at: 200)
        add("미분류2", nil, at: 300)
        try context.save()

        let library = RecordingLibrary(context: context)
        #expect(library.selection == .unclassified)
        #expect(library.recordings.map(\.title) == ["미분류2", "미분류1"])
        #expect(library.unclassifiedCount == 2)
    }

    @Test func 녹음이_없는_과목은_빈_목록이다() throws {
        let library = RecordingLibrary(context: context)
        library.select(.subject(ds.persistentModelID))
        #expect(library.recordings.isEmpty)
        #expect(library.count(for: ds) == 0)
    }

    @Test func 새_녹음은_reload로_반영된다() throws {
        let library = RecordingLibrary(context: context)
        library.select(.subject(ds.persistentModelID))
        add("새 녹음", ds, at: 100)
        try context.save()
        #expect(library.recordings.isEmpty)
        library.reload()
        #expect(library.recordings.map(\.title) == ["새 녹음"])
        #expect(library.count(for: ds) == 1)
    }

    @Test func 과목을_지우면_녹음이_미분류_목록으로_옮겨진다() throws {
        add("월", ds, at: 100)
        try context.save()
        let library = RecordingLibrary(context: context)
        context.delete(ds)
        try context.save()
        library.select(.unclassified)
        library.reload()
        #expect(library.recordings.map(\.title) == ["월"])
        #expect(library.unclassifiedCount == 1)
    }

    @Test func 고른_과목이_지워지면_미분류로_돌아간다() throws {
        add("월", ds, at: 100)
        try context.save()
        let library = RecordingLibrary(context: context)
        library.select(.subject(ds.persistentModelID))
        context.delete(ds)
        try context.save()
        library.reload()
        #expect(library.selection == .unclassified)
    }
}
#endif
