#if canImport(SwiftData)
import Foundation
import SwiftData
import Testing
@testable import LectureCore

@MainActor
@Suite struct RecordingMigratorTests {
    let container: ModelContainer
    let files = FakeFileStore()
    let storage: RecordingStorage
    var context: ModelContext { container.mainContext }

    init() throws {
        container = try LectureModelContainer.make(inMemory: true)
        storage = RecordingStorage(root: URL(filePath: "/tmp/LectureRecorderTests/Recordings", directoryHint: .isDirectory), files: files)
    }

    var migrator: RecordingMigrator { RecordingMigrator(context: context, storage: storage, calendar: seoulCalendar) }

    func subject(_ name: String, semester: String) -> Subject {
        let subject = Subject(name: name)
        subject.semester = semester
        context.insert(subject)
        return subject
    }

    @discardableResult
    func addRecording(_ path: String, subject: Subject?, startedAt: Date = date(2026, 10, 28, 13, 30), size: Int64 = 1_000) throws -> Recording {
        let recording = Recording(title: "녹음", subject: subject, startedAt: startedAt, duration: 60, relativePath: path)
        context.insert(recording)
        try context.save()
        let url = storage.url(for: path)
        files.add(url)
        files.sizes[url.standardizedFileURL.path] = size
        return recording
    }

    @Test func 학기를_아는_과목의_녹음을_새_폴더로_옮긴다() async throws {
        let cs = subject("컴퓨터구조", semester: "2026년 2학기")
        let recording = try addRecording("컴퓨터구조/2026-10-28_1330.m4a", subject: cs)

        let report = await migrator.migrateIfNeeded()

        #expect(report == RecordingMigrationReport(moved: 1))
        #expect(recording.relativePath == "2026년 2학기/컴퓨터구조/10-28 수 13-30.m4a")
        #expect(files.fileExists(at: storage.url(for: "2026년 2학기/컴퓨터구조/10-28 수 13-30.m4a")))
        #expect(!files.fileExists(at: storage.url(for: "컴퓨터구조/2026-10-28_1330.m4a")))
    }

    @Test func 미분류_녹음도_새_이름으로_옮긴다() async throws {
        let recording = try addRecording("미분류/2026-10-28_1330.m4a", subject: nil)

        let report = await migrator.migrateIfNeeded()

        #expect(report.moved == 1)
        #expect(recording.relativePath == "미분류/10-28 수 13-30.m4a")
        #expect(!files.fileExists(at: storage.url(for: "미분류/2026-10-28_1330.m4a")))
    }

    @Test func 학기를_모르는_과목의_녹음은_그대로_둔다() async throws {
        let ds = subject("자료구조", semester: "")
        let recording = try addRecording("자료구조/2026-10-28_1330.m4a", subject: ds)

        let report = await migrator.migrateIfNeeded()

        #expect(report == RecordingMigrationReport())
        #expect(recording.relativePath == "자료구조/2026-10-28_1330.m4a")
        #expect(files.fileExists(at: storage.url(for: "자료구조/2026-10-28_1330.m4a")))
    }

    @Test func 압축_전_CAF는_건드리지_않는다() async throws {
        let cs = subject("컴퓨터구조", semester: "2026년 2학기")
        let recording = try addRecording("컴퓨터구조/2026-10-28_1330.caf", subject: cs)

        let report = await migrator.migrateIfNeeded()

        #expect(report == RecordingMigrationReport())
        #expect(recording.relativePath == "컴퓨터구조/2026-10-28_1330.caf")
    }

    @Test func 복사에_실패하면_원본과_경로를_그대로_둔다() async throws {
        let cs = subject("컴퓨터구조", semester: "2026년 2학기")
        let recording = try addRecording("컴퓨터구조/2026-10-28_1330.m4a", subject: cs)
        files.failNextCopy = true

        let report = await migrator.migrateIfNeeded()

        #expect(report == RecordingMigrationReport(failed: 1))
        #expect(recording.relativePath == "컴퓨터구조/2026-10-28_1330.m4a")
        #expect(files.fileExists(at: storage.url(for: "컴퓨터구조/2026-10-28_1330.m4a")))
        #expect(!files.fileExists(at: storage.url(for: "2026년 2학기/컴퓨터구조/10-28 수 13-30.m4a")))
    }

    @Test func 복사본_크기가_다르면_복사본을_지우고_원본을_둔다() async throws {
        let cs = subject("컴퓨터구조", semester: "2026년 2학기")
        let recording = try addRecording("컴퓨터구조/2026-10-28_1330.m4a", subject: cs)
        files.corruptNextCopy = true

        let report = await migrator.migrateIfNeeded()

        #expect(report == RecordingMigrationReport(failed: 1))
        #expect(recording.relativePath == "컴퓨터구조/2026-10-28_1330.m4a")
        #expect(files.fileExists(at: storage.url(for: "컴퓨터구조/2026-10-28_1330.m4a")))
        #expect(!files.fileExists(at: storage.url(for: "2026년 2학기/컴퓨터구조/10-28 수 13-30.m4a")))
    }

    @Test func 파일이_없으면_경로를_바꾸지_않는다() async throws {
        let cs = subject("컴퓨터구조", semester: "2026년 2학기")
        let recording = try addRecording("컴퓨터구조/2026-10-28_1330.m4a", subject: cs)
        try files.removeItem(at: storage.url(for: recording.relativePath))

        let report = await migrator.migrateIfNeeded()

        #expect(report == RecordingMigrationReport(missing: 1))
        #expect(recording.relativePath == "컴퓨터구조/2026-10-28_1330.m4a")
    }

    @Test func 같은_분의_녹음_두_개는_번호를_붙여_둘_다_옮긴다() async throws {
        let cs = subject("컴퓨터구조", semester: "2026년 2학기")
        let first = try addRecording("컴퓨터구조/2026-10-28_1330.m4a", subject: cs)
        let second = try addRecording("컴퓨터구조/2026-10-28_1330_2.m4a", subject: cs)

        let report = await migrator.migrateIfNeeded()

        #expect(report.moved == 2)
        #expect(Set([first.relativePath, second.relativePath]) == [
            "2026년 2학기/컴퓨터구조/10-28 수 13-30.m4a",
            "2026년 2학기/컴퓨터구조/10-28 수 13-30_2.m4a",
        ])
    }

    @Test func 두_번_실행해도_결과가_같다() async throws {
        let cs = subject("컴퓨터구조", semester: "2026년 2학기")
        let recording = try addRecording("컴퓨터구조/2026-10-28_1330.m4a", subject: cs)

        await migrator.migrateIfNeeded()
        let report = await migrator.migrateIfNeeded()

        #expect(report == RecordingMigrationReport())
        #expect(recording.relativePath == "2026년 2학기/컴퓨터구조/10-28 수 13-30.m4a")
    }

    @Test func 하나가_실패해도_나머지는_옮긴다() async throws {
        let cs = subject("컴퓨터구조", semester: "2026년 2학기")
        let bad = try addRecording("컴퓨터구조/2026-10-28_1330.m4a", subject: cs)
        let good = try addRecording("컴퓨터구조/2026-11-04_1330.m4a", subject: cs, startedAt: date(2026, 11, 4, 13, 30))
        files.failNextCopy = true

        let report = await migrator.migrateIfNeeded()

        #expect(report.moved + report.failed == 2)
        #expect(report.failed == 1)
        // 어느 쪽이 실패했든 기록이 가리키는 파일은 항상 존재한다.
        for recording in [bad, good] {
            #expect(files.fileExists(at: storage.url(for: recording.relativePath)))
        }
    }
}
#endif
