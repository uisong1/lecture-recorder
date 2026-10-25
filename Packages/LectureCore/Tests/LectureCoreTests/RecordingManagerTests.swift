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
        #expect(recording.relativePath == "학기 미정/자료구조/2026-03-02_1000.m4a")
        #expect(files.fileExists(at: storage.url(for: "학기 미정/자료구조/2026-03-02_1000.m4a")))
        #expect(!files.fileExists(at: storage.url(for: "미분류/2026-03-02_1000.m4a")))
    }

    @Test func 압축_전_CAF를_옮겨도_확장자는_CAF로_남는다() throws {
        let ds = try SubjectManager(context: context).add(name: "자료구조", color: .green)
        let recording = addRecording("미분류/a.caf")
        try makeManager().move(recording, to: ds)
        #expect(recording.relativePath == "학기 미정/자료구조/a.caf")
        #expect(files.fileExists(at: storage.url(for: "학기 미정/자료구조/a.caf")))
    }

    @Test func 내보내면_원본은_그대로_두고_복사본이_생긴다() throws {
        let recording = addRecording("자료구조/a.m4a")
        let destination = URL(filePath: "/tmp/내보내기/a.m4a")
        try makeManager().export(recording, to: destination)
        #expect(files.fileExists(at: destination))
        #expect(files.fileExists(at: storage.url(for: "자료구조/a.m4a")))
    }

    @Test func 묶음으로_내보내면_북마크와_과목이_글에_담긴다() throws {
        let ds = try SubjectManager(context: context).add(name: "자료구조", color: .green)
        let recording = addRecording("자료구조/a.m4a", subject: ds)
        context.insert(Bookmark(time: 90, note: "중요", createdAt: date(2026, 3, 2, 10, 2), recording: recording))
        try context.save()
        let parent = URL(filePath: "/tmp/내보내기", directoryHint: .isDirectory)
        let manager = makeManager()
        let result = try manager.exportBundle([recording], label: "자료구조", to: parent, now: date(2026, 10, 25, 9, 0), calendar: seoulCalendar)
        #expect(result.exportedCount == 1)
        let summary = result.folder.appending(path: RecordingBundleExporter.summaryFileName)
        let text = String(decoding: files.written[summary.standardizedFileURL.path] ?? Data(), as: UTF8.self)
        #expect(text.contains("01:30 — 중요"))
        #expect(text.contains("## 자료구조"))
        #expect(files.fileExists(at: storage.url(for: "자료구조/a.m4a")))
        #expect(manager.errorMessage == nil)
    }

    @Test func 묶음_내보내기가_실패하면_이유를_알린다() throws {
        let recording = addRecording("자료구조/a.m4a")
        files.failNextCopy = true
        let manager = makeManager()
        #expect(throws: RecordingBundleError.self) {
            try manager.exportBundle([recording], label: "자료구조", to: URL(filePath: "/tmp/내보내기"), now: date(2026, 10, 25, 9, 0))
        }
        #expect(manager.errorMessage?.hasPrefix("묶음을 만들지 못했습니다") == true)
    }

    @Test func 원본이_없으면_내보내지_않고_안내한다() throws {
        let recording = addRecording("자료구조/a.m4a")
        try files.removeItem(at: storage.url(for: "자료구조/a.m4a"))
        let manager = makeManager()
        #expect(throws: RecordingManagerError.fileMissing) { try manager.export(recording, to: URL(filePath: "/tmp/내보내기/a.m4a")) }
        #expect(manager.errorMessage == "녹음 파일을 찾을 수 없습니다.")
    }

    @Test func 복사에_실패하면_이유를_알리고_원본은_남는다() throws {
        let recording = addRecording("자료구조/a.m4a")
        files.failNextCopy = true
        let manager = makeManager()
        #expect(throws: (any Error).self) { try manager.export(recording, to: URL(filePath: "/tmp/내보내기/a.m4a")) }
        #expect(manager.errorMessage?.hasPrefix("녹음을 저장하지 못했습니다") == true)
        #expect(files.fileExists(at: storage.url(for: "자료구조/a.m4a")))
        #expect(!files.fileExists(at: URL(filePath: "/tmp/내보내기/a.m4a")))
    }

    @Test func 저장_대화상자의_기본_이름은_제목과_확장자다() throws {
        let recording = addRecording("자료구조/a.m4a")
        recording.title = "자료구조 3/2 1주차"
        #expect(makeManager().suggestedExportName(for: recording) == "자료구조 3-2 1주차.m4a")
        let working = addRecording("자료구조/b.caf")
        working.title = "작업 중"
        #expect(makeManager().suggestedExportName(for: working) == "작업 중.caf")
    }

    @Test func 파일이_있으면_공유할_위치를_돌려준다() throws {
        let recording = addRecording("자료구조/a.m4a")
        #expect(makeManager().shareURL(for: recording) == storage.url(for: "자료구조/a.m4a"))
    }

    @Test func 파일이_없으면_공유하지_않는다() throws {
        let recording = addRecording("자료구조/a.m4a")
        try files.removeItem(at: storage.url(for: "자료구조/a.m4a"))
        #expect(makeManager().shareURL(for: recording) == nil)
    }

    @Test func 파일_위치를_돌려준다() throws {
        let recording = addRecording("자료구조/a.m4a")
        #expect(makeManager().fileURL(for: recording) == storage.url(for: "자료구조/a.m4a"))
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
        ds.semester = "2026년 2학기"
        _ = addRecording("2026년 2학기/자료구조/a.m4a", subject: ds)
        let recording = addRecording("미분류/a.m4a")
        try makeManager().move(recording, to: ds)
        #expect(recording.relativePath == "2026년 2학기/자료구조/a_2.m4a")
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

    @Test func 휴지통으로_보내면_파일은_휴지통에_가고_기록은_사라진다() throws {
        let recording = addRecording("미분류/a.m4a")
        try makeManager().trash(recording)
        #expect(files.trashed == [storage.url(for: "미분류/a.m4a").standardizedFileURL.path])
        #expect(!files.fileExists(at: storage.url(for: "미분류/a.m4a")))
        #expect(try context.fetch(FetchDescriptor<Recording>()).isEmpty)
    }

    @Test func 휴지통으로_보내지_못하면_파일도_기록도_그대로_두고_오류를_남긴다() throws {
        let recording = addRecording("미분류/a.m4a")
        files.failNextTrash = true
        let manager = makeManager()
        #expect(throws: RecordingManagerError.self) { try manager.trash(recording) }
        #expect(files.fileExists(at: storage.url(for: "미분류/a.m4a")))
        #expect(files.trashed.isEmpty)
        #expect(try context.fetch(FetchDescriptor<Recording>()).count == 1)
        #expect(manager.errorMessage?.hasPrefix("녹음 파일을 처리하지 못했습니다") == true)
    }

    @Test func 파일이_이미_없어도_휴지통_삭제는_기록을_지운다() throws {
        let recording = addRecording("미분류/a.m4a")
        try files.removeItem(at: storage.url(for: "미분류/a.m4a"))
        try makeManager().trash(recording)
        #expect(files.trashed.isEmpty)
        #expect(try context.fetch(FetchDescriptor<Recording>()).isEmpty)
    }

    @Test func 영구_삭제는_휴지통을_거치지_않는다() throws {
        let recording = addRecording("미분류/a.m4a")
        try makeManager().delete(recording)
        #expect(files.trashed.isEmpty)
    }

    @Test func 파일이_이미_없어도_기록은_지운다() throws {
        let recording = addRecording("미분류/a.m4a")
        try files.removeItem(at: storage.url(for: "미분류/a.m4a"))
        try makeManager().delete(recording)
        #expect(try context.fetch(FetchDescriptor<Recording>()).isEmpty)
    }

    @Test func 파일이_없는_녹음은_재생하지_않고_안내를_남긴다() {
        let recording = Recording(title: "녹음", subject: nil, startedAt: date(2026, 3, 2, 10, 0), duration: 60, relativePath: "미분류/없는.m4a")
        context.insert(recording)
        let manager = makeManager()

        #expect(!manager.canPlay(recording))
        #expect(manager.errorMessage == RecordingRowStatus.missingFileNotice)
        #expect(manager.status(for: recording).labels == ["파일 없음"])
    }

    @Test func 파일이_있으면_재생해도_되고_이전_안내를_지운다() {
        let recording = addRecording("미분류/a.m4a")
        let manager = makeManager()
        manager.errorMessage = "이전 오류"

        #expect(manager.canPlay(recording))
        #expect(manager.errorMessage == nil)
    }

    @Test func 제목_끝에_복구됨이_붙은_예전_기록도_복구된_녹음이다() {
        let legacy = Recording(title: "자료구조 (복구됨)", subject: nil, startedAt: date(2026, 3, 2, 10, 0), duration: 60, relativePath: "a.m4a")
        let flagged = Recording(title: "자료구조", subject: nil, startedAt: date(2026, 3, 2, 10, 0), duration: 60, relativePath: "b.m4a")
        flagged.wasRecovered = true
        let plain = Recording(title: "자료구조", subject: nil, startedAt: date(2026, 3, 2, 10, 0), duration: 60, relativePath: "c.m4a")
        #expect(legacy.isRecovered)
        #expect(flagged.isRecovered)
        #expect(!plain.isRecovered)
    }
}
#endif
