#if canImport(SwiftData)
import Foundation
import SwiftData
import Testing
@testable import LectureCore

@MainActor
@Suite struct RecordingManagerTests {
    let container: ModelContainer
    let files = FakeFileStore()
    let storage: RecordingStorage
    var context: ModelContext { container.mainContext }

    init() throws {
        container = try LectureModelContainer.make(inMemory: true)
        storage = RecordingStorage(root: URL(filePath: "/tmp/LectureRecorderTests/Recordings", directoryHint: .isDirectory), files: files)
    }

    func makeManager() -> RecordingManager { RecordingManager(context: context, storage: storage) }

    func addRecording(_ path: String, subject: Subject? = nil) -> Recording {
        let recording = Recording(title: "녹음", subject: subject, startedAt: date(2026, 3, 2, 10, 0), duration: 60, relativePath: path)
        context.insert(recording)
        files.add(storage.url(for: path))
        return recording
    }

    @Test func 제목을_바꾸면_저장되고_파일은_그대로다() throws {
        let recording = addRecording("미분류/2026-03-02_1000.m4a")
        try makeManager().rename(recording, to: "  1주차 강의  ")
        #expect(recording.title == "1주차 강의")
        #expect(recording.relativePath == "미분류/2026-03-02_1000.m4a")
    }

    @Test func 빈_제목은_거부한다() throws {
        let recording = addRecording("미분류/a.m4a")
        let manager = makeManager()
        #expect(throws: RecordingManagerError.emptyTitle) { try manager.rename(recording, to: "   ") }
        #expect(recording.title == "녹음")
        #expect(manager.errorMessage == "제목을 입력하세요.")
    }

    @Test func 과목을_옮기면_파일과_기록이_함께_바뀐다() throws {
        let ds = try SubjectManager(context: context).add(name: "자료구조", color: .green)
        let recording = addRecording("미분류/2026-03-02_1000.m4a")
        try makeManager().move(recording, to: ds)
        #expect(recording.subject === ds)
        #expect(recording.relativePath == "자료구조/2026-03-02_1000.m4a")
        #expect(files.fileExists(at: storage.url(for: "자료구조/2026-03-02_1000.m4a")))
        #expect(!files.fileExists(at: storage.url(for: "미분류/2026-03-02_1000.m4a")))
    }

    @Test func 미분류로_옮길_수_있다() throws {
        let ds = try SubjectManager(context: context).add(name: "자료구조", color: .green)
        let recording = addRecording("자료구조/a.m4a", subject: ds)
        try makeManager().move(recording, to: nil)
        #expect(recording.subject == nil)
        #expect(recording.relativePath == "미분류/a.m4a")
    }

    @Test func 옮길_곳에_같은_이름이_있으면_번호를_붙인다() throws {
        let ds = try SubjectManager(context: context).add(name: "자료구조", color: .green)
        _ = addRecording("자료구조/a.m4a", subject: ds)
        let recording = addRecording("미분류/a.m4a")
        try makeManager().move(recording, to: ds)
        #expect(recording.relativePath == "자료구조/a_2.m4a")
    }

    @Test func 같은_과목으로_옮기면_아무것도_하지_않는다() throws {
        let recording = addRecording("미분류/a.m4a")
        try makeManager().move(recording, to: nil)
        #expect(recording.relativePath == "미분류/a.m4a")
    }

    @Test func 파일_이동이_실패하면_기록을_바꾸지_않는다() throws {
        let ds = try SubjectManager(context: context).add(name: "자료구조", color: .green)
        let recording = addRecording("미분류/a.m4a")
        files.failNextMove = true
        let manager = makeManager()
        #expect(throws: RecordingManagerError.self) { try manager.move(recording, to: ds) }
        #expect(recording.subject == nil)
        #expect(recording.relativePath == "미분류/a.m4a")
        #expect(manager.errorMessage?.hasPrefix("녹음 파일을 처리하지 못했습니다") == true)
    }

    @Test func 삭제하면_파일과_기록이_모두_사라진다() throws {
        let recording = addRecording("미분류/a.m4a")
        try makeManager().delete(recording)
        #expect(!files.fileExists(at: storage.url(for: "미분류/a.m4a")))
        #expect(try context.fetch(FetchDescriptor<Recording>()).isEmpty)
    }

    @Test func 파일이_이미_없어도_기록은_지운다() throws {
        let recording = addRecording("미분류/a.m4a")
        try files.removeItem(at: storage.url(for: "미분류/a.m4a"))
        try makeManager().delete(recording)
        #expect(try context.fetch(FetchDescriptor<Recording>()).isEmpty)
    }
}
#endif
