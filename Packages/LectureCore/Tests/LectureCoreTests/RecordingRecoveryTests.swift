#if canImport(SwiftData)
import Foundation
import SwiftData
import Testing
@testable import LectureCore

@MainActor
@Suite struct RecordingRecoveryTests {
    let container: ModelContainer
    let files = FakeFileStore()
    let root = URL(filePath: "/tmp/LectureRecorderTests/Recordings", directoryHint: .isDirectory)
    let startedAt = date(2026, 3, 2, 10, 0)

    init() throws {
        container = try LectureModelContainer.make(inMemory: true)
    }

    func makeRecovery(journal: InMemoryRecordingJournal) -> RecordingRecovery {
        RecordingRecovery(
            context: container.mainContext,
            storage: RecordingStorage(root: root, files: files),
            files: files,
            journal: journal,
            calendar: seoulCalendar
        )
    }

    func pending(_ name: String? = "자료구조") -> PendingRecording {
        PendingRecording(relativePath: "\(name ?? "미분류")/2026-03-02_1000.m4a", subjectName: name, startedAt: startedAt)
    }

    func addFile(_ pending: PendingRecording, bytes: Int64) {
        let url = root.appending(path: pending.relativePath)
        files.add(url)
        files.sizes[url.standardizedFileURL.path] = bytes
    }

    @Test func 남은_파일이_있으면_녹음을_되살린다() throws {
        let subject = try SubjectManager(context: container.mainContext).add(name: "자료구조", color: .green)
        let p = pending()
        addFile(p, bytes: 240_000) // 32kbps = 초당 4,000바이트 → 60초
        let journal = InMemoryRecordingJournal(pending: p)

        let recovered = try #require(try makeRecovery(journal: journal).recoverIfNeeded())

        #expect(recovered.subject === subject)
        #expect(recovered.relativePath == p.relativePath)
        #expect(recovered.startedAt == startedAt)
        #expect(recovered.duration == 60)
        #expect(recovered.title == "자료구조 3월 2일 10:00")
        #expect(recovered.wasRecovered)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Recording>()) == 1)
        #expect(journal.load() == nil)
    }

    @Test func CAF가_남았으면_PCM_비트레이트로_길이를_어림한다() throws {
        let p = PendingRecording(relativePath: "자료구조/2026-03-02_1000.caf", subjectName: nil, startedAt: startedAt)
        addFile(p, bytes: 1_920_000) // 256kbps = 초당 32,000바이트 → 60초
        let recovered = try #require(try makeRecovery(journal: InMemoryRecordingJournal(pending: p)).recoverIfNeeded())
        #expect(recovered.relativePath == p.relativePath)
        #expect(recovered.duration == 60)
    }

    @Test func 과목이_없으면_미분류로_되살린다() throws {
        let p = pending(nil)
        addFile(p, bytes: 8_000)
        let recovered = try #require(try makeRecovery(journal: InMemoryRecordingJournal(pending: p)).recoverIfNeeded())
        #expect(recovered.subject == nil)
        #expect(recovered.title.hasPrefix("미분류"))
    }

    @Test func 저널이_비어_있으면_아무것도_하지_않는다() throws {
        #expect(try makeRecovery(journal: InMemoryRecordingJournal()).recoverIfNeeded() == nil)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Recording>()) == 0)
    }

    @Test func 파일이_없으면_저널만_지운다() throws {
        let journal = InMemoryRecordingJournal(pending: pending())
        #expect(try makeRecovery(journal: journal).recoverIfNeeded() == nil)
        #expect(journal.load() == nil)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Recording>()) == 0)
    }

    @Test func 이미_저장된_녹음은_중복으로_만들지_않는다() throws {
        let p = pending()
        addFile(p, bytes: 8_000)
        container.mainContext.insert(Recording(title: "이미 있음", subject: nil, startedAt: startedAt, duration: 1, relativePath: p.relativePath))
        try container.mainContext.save()
        let journal = InMemoryRecordingJournal(pending: p)

        #expect(try makeRecovery(journal: journal).recoverIfNeeded() == nil)
        #expect(journal.load() == nil)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Recording>()) == 1)
    }

    @Test func 되살린_녹음에_북마크_시점도_되살린다() throws {
        let p = PendingRecording(relativePath: "자료구조/2026-03-02_1000.caf", subjectName: nil, startedAt: startedAt, bookmarkTimes: [30, 45, 999])
        addFile(p, bytes: 1_920_000) // 60초
        let recovered = try #require(try makeRecovery(journal: InMemoryRecordingJournal(pending: p)).recoverIfNeeded())
        #expect(recovered.sortedBookmarks.map(\.time) == [30, 45, 60])
    }

    @Test func 되살린_북마크에_메모도_되살린다() throws {
        let p = PendingRecording(relativePath: "자료구조/2026-03-02_1000.caf", subjectName: nil, startedAt: startedAt, bookmarkTimes: [30, 45, 50], bookmarkNotes: ["정의", ""])
        addFile(p, bytes: 1_920_000)
        let recovered = try #require(try makeRecovery(journal: InMemoryRecordingJournal(pending: p)).recoverIfNeeded())
        #expect(recovered.sortedBookmarks.map(\.note) == ["정의", "", ""])
    }
}

@MainActor
@Suite struct UnsavedRecordingRecoveryTests {
    let container: ModelContainer
    let files = FakeFileStore()
    let root = URL(filePath: "/tmp/LectureRecorderTests/Recordings", directoryHint: .isDirectory)

    init() throws {
        container = try LectureModelContainer.make(inMemory: true)
    }

    func makeRecovery(journal: InMemoryRecordingJournal) -> RecordingRecovery {
        RecordingRecovery(context: container.mainContext, storage: RecordingStorage(root: root, files: files), files: files, journal: journal, calendar: seoulCalendar)
    }

    func entry(_ path: String, hour: Int) -> PendingRecording {
        let pending = PendingRecording(relativePath: path, subjectName: nil, startedAt: date(2026, 3, 2, hour, 0), bookmarkTimes: [10])
        let url = root.appending(path: path)
        files.add(url)
        files.sizes[url.standardizedFileURL.path] = 1_920_000
        return pending
    }

    @Test func 보관된_앞_녹음과_저널의_녹음을_모두_되살린다() throws {
        let kept = entry("미분류/03-02 월 10-00.caf", hour: 10)
        let current = entry("미분류/03-02 월 14-00.caf", hour: 14)
        let journal = InMemoryRecordingJournal(pending: current, unsaved: [kept])
        try makeRecovery(journal: journal).recoverIfNeeded()
        let paths = try container.mainContext.fetch(FetchDescriptor<Recording>()).map(\.relativePath).sorted()
        #expect(paths == ["미분류/03-02 월 10-00.caf", "미분류/03-02 월 14-00.caf"])
        #expect(journal.load() == nil)
        #expect(journal.loadUnsaved().isEmpty)
    }

    @Test func 보관된_기록만_있어도_되살린다() throws {
        let kept = entry("미분류/03-02 월 10-00.caf", hour: 10)
        let journal = InMemoryRecordingJournal(unsaved: [kept])
        let recovered = try #require(try makeRecovery(journal: journal).recoverIfNeeded())
        #expect(recovered.wasRecovered)
        #expect(recovered.sortedBookmarks.count == 1)
        #expect(journal.loadUnsaved().isEmpty)
    }

    @Test func 이미_저장된_녹음의_보관_기록과_파일이_없는_기록은_복구_없이_지운다() throws {
        let saved = entry("미분류/03-02 월 10-00.caf", hour: 10)
        container.mainContext.insert(Recording(title: "저장됨", subject: nil, startedAt: saved.startedAt, duration: 60, relativePath: saved.relativePath))
        try container.mainContext.save()
        let missing = PendingRecording(relativePath: "미분류/없는.caf", subjectName: nil, startedAt: date(2026, 3, 2, 12, 0))
        let journal = InMemoryRecordingJournal(unsaved: [saved, missing])
        #expect(try makeRecovery(journal: journal).recoverIfNeeded() == nil)
        #expect(journal.loadUnsaved().isEmpty)
    }
}

@Suite struct FileRecordingJournalTests {
    @Test func 파일에_쓰고_읽고_지운다() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "journal-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let journal = FileRecordingJournal(url: url)
        #expect(journal.load() == nil)
        let pending = PendingRecording(relativePath: "미분류/a.m4a", subjectName: nil, startedAt: Date(timeIntervalSince1970: 1_000))
        try journal.save(pending)
        #expect(journal.load() == pending)
        journal.clear()
        #expect(journal.load() == nil)
        journal.clear() // 없어도 오류 없이 지나간다
    }

    @Test func 보관한_기록을_파일에_쓰고_같은_경로는_바꿔_쓰고_지운다() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "journal-\(UUID().uuidString).json")
        let journal = FileRecordingJournal(url: url)
        defer { try? FileManager.default.removeItem(at: journal.unsavedURL) }
        #expect(journal.loadUnsaved().isEmpty)
        let a = PendingRecording(relativePath: "a/1.caf", subjectName: nil, startedAt: Date(timeIntervalSince1970: 1_000))
        let b = PendingRecording(relativePath: "a/2.caf", subjectName: "자료구조", startedAt: Date(timeIntervalSince1970: 2_000), bookmarkTimes: [5])
        try journal.keepUnsaved(a)
        try journal.keepUnsaved(b)
        try journal.keepUnsaved(a)
        #expect(journal.loadUnsaved() == [b, a])
        journal.clearUnsaved(relativePath: "a/2.caf")
        #expect(journal.loadUnsaved() == [a])
        journal.clearUnsaved(relativePath: "a/1.caf")
        #expect(journal.loadUnsaved().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: journal.unsavedURL.path))
        // 보관 기록은 저널 본체와 따로다.
        try journal.save(a)
        try journal.keepUnsaved(b)
        journal.clear()
        #expect(journal.load() == nil)
        #expect(journal.loadUnsaved() == [b])
    }

    @Test func 북마크가_없던_이전_저널도_읽는다() throws {
        let json = #"{"relativePath":"a/b.m4a","startedAt":0}"#
        let decoded = try JSONDecoder().decode(PendingRecording.self, from: Data(json.utf8))
        #expect(decoded.bookmarkTimes.isEmpty)
        #expect(decoded.bookmarkNotes.isEmpty)
        #expect(decoded.subjectName == nil)
    }

    @Test func 북마크_시점이_저널_파일에_저장되고_다시_읽힌다() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "journal-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let journal = FileRecordingJournal(url: url)
        let p = PendingRecording(relativePath: "a/b.caf", subjectName: "자료구조", startedAt: Date(timeIntervalSince1970: 1_000), bookmarkTimes: [12.5, 99], bookmarkNotes: ["메모", ""])
        try journal.save(p)
        #expect(journal.load() == p)
    }
}
#endif
