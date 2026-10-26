#if canImport(SwiftData)
import Foundation
import SwiftData
import Testing
@testable import LectureCore

@MainActor
@Suite struct SavedRecordingEditorTests {
    let container: ModelContainer
    let files = FakeFileStore()
    let storage: RecordingStorage
    let manager: RecordingManager
    var context: ModelContext { container.mainContext }

    init() throws {
        container = try LectureModelContainer.make(inMemory: true)
        storage = RecordingStorage(root: URL(filePath: "/tmp/LectureRecorderTests/Recordings", directoryHint: .isDirectory), files: files)
        manager = RecordingManager(context: container.mainContext, storage: storage)
    }

    func addRecording() -> Recording {
        let recording = Recording(title: "녹음", subject: nil, startedAt: date(2026, 3, 2, 10, 0), duration: 60, relativePath: "미분류/a.m4a")
        context.insert(recording)
        files.add(storage.url(for: recording.relativePath))
        return recording
    }

    @Test func 제목과_메모를_한_번에_저장하고_칸을_닫는다() {
        let recording = addRecording()
        var changes = 0
        let editor = SavedRecordingEditor(manager: manager) { changes += 1 }
        editor.begin(recording)
        editor.title = "1주차"
        editor.memo = "과제 공지"
        #expect(editor.save(recording))
        #expect(recording.title == "1주차")
        #expect(recording.memo == "과제 공지")
        #expect(!editor.isEditing)
        #expect(editor.errorMessage == nil)
        #expect(changes == 1)
    }

    @Test func 저장이_실패하면_칸을_열어_둔_채_문구가_남는다() {
        let recording = addRecording()
        let editor = SavedRecordingEditor(manager: manager)
        editor.begin(recording)
        editor.title = "   "
        #expect(!editor.save(recording))
        #expect(editor.isEditing)
        #expect(editor.errorMessage == "제목을 입력하세요.")
        #expect(recording.title == "녹음")
    }

    @Test func 과목_이동이_실패하면_문구가_남고_다시_성공하면_지워진다() throws {
        let subject = try SubjectManager(context: context).add(name: "자료구조", color: .green)
        let recording = addRecording()
        let editor = SavedRecordingEditor(manager: manager)
        files.failNextMove = true
        #expect(!editor.move(recording, to: subject))
        #expect(editor.errorMessage?.contains("녹음 파일을 처리하지 못했습니다") == true)
        #expect(recording.subject == nil)
        #expect(editor.move(recording, to: subject))
        #expect(editor.errorMessage == nil)
        #expect(recording.subject === subject)
    }

    @Test func 닫으면_오류_문구도_지운다() {
        let recording = addRecording()
        let editor = SavedRecordingEditor(manager: manager)
        editor.begin(recording)
        editor.title = ""
        editor.save(recording)
        editor.cancel()
        #expect(!editor.isEditing)
        #expect(editor.errorMessage == nil)
    }
}
#endif
