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
        #expect(recovered.title == "자료구조 3월 2일 10:00 (복구됨)")
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
}
#endif
