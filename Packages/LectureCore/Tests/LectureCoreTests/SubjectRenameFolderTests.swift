#if canImport(SwiftData)
import Foundation
import SwiftData
import Testing
@testable import LectureCore

@MainActor
@Suite struct SubjectRenameFolderTests {
    let container: ModelContainer
    let files = FakeFileStore()
    let storage: RecordingStorage
    let manager: SubjectManager
    var context: ModelContext { container.mainContext }
    static let semester = "2026년 2학기"

    init() throws {
        container = try LectureModelContainer.make(inMemory: true)
        storage = RecordingStorage(root: URL(filePath: "/tmp/LectureRecorderTests/Recordings", directoryHint: .isDirectory), files: files)
        manager = SubjectManager(context: container.mainContext, storage: storage)
    }

    func makeSubject(_ name: String) throws -> Subject {
        let subject = try manager.add(name: name, color: .blue)
        subject.semester = Self.semester
        try context.save()
        return subject
    }

    @discardableResult
    func addRecording(_ path: String, subject: Subject?, withFile: Bool = true) throws -> Recording {
        let recording = Recording(title: "녹음", subject: subject, startedAt: date(2026, 10, 28, 13, 30), duration: 60, relativePath: path)
        context.insert(recording)
        try context.save()
        if withFile {
            let url = storage.url(for: path)
            files.add(url)
            files.sizes[url.standardizedFileURL.path] = 1_000
        }
        return recording
    }

    func exists(_ path: String) -> Bool { files.fileExists(at: storage.url(for: path)) }

    @Test func 이름을_바꾸면_폴더와_녹음_경로가_따라간다() throws {
        let subject = try makeSubject("컴구")
        let first = try addRecording("2026년 2학기/컴구/10-28 수 13-30.m4a", subject: subject)
        let second = try addRecording("2026년 2학기/컴구/11-04 수 13-30.m4a", subject: subject)

        try manager.rename(subject, to: "컴퓨터구조")

        #expect(subject.name == "컴퓨터구조")
        #expect(first.relativePath == "2026년 2학기/컴퓨터구조/10-28 수 13-30.m4a")
        #expect(second.relativePath == "2026년 2학기/컴퓨터구조/11-04 수 13-30.m4a")
        #expect(exists(first.relativePath) && exists(second.relativePath))
        #expect(!exists("2026년 2학기/컴구/10-28 수 13-30.m4a"))
        #expect(files.sizes[storage.url(for: first.relativePath).standardizedFileURL.path] == 1_000)
    }

    @Test func 이미_있는_이름의_폴더면_거부하고_아무것도_바꾸지_않는다() throws {
        let subject = try makeSubject("컴구")
        let recording = try addRecording("2026년 2학기/컴구/10-28 수 13-30.m4a", subject: subject)
        // 과목은 없지만 폴더만 남아 있는 이름 (예전에 지운 과목의 녹음).
        try addRecording("2026년 2학기/컴퓨터구조/09-02 수 13-30.m4a", subject: nil)

        #expect(throws: SubjectError.folderExists("컴퓨터구조")) { try manager.rename(subject, to: "컴퓨터구조") }

        #expect(subject.name == "컴구")
        #expect(recording.relativePath == "2026년 2학기/컴구/10-28 수 13-30.m4a")
        #expect(exists("2026년 2학기/컴구/10-28 수 13-30.m4a"))
        #expect(exists("2026년 2학기/컴퓨터구조/09-02 수 13-30.m4a"))
    }

    @Test func 폴더_이동이_실패하면_이름과_경로가_이전_상태로_남는다() throws {
        let subject = try makeSubject("컴구")
        let recording = try addRecording("2026년 2학기/컴구/10-28 수 13-30.m4a", subject: subject)
        files.failNextMove = true

        #expect(throws: SubjectError.self) { try manager.rename(subject, to: "컴퓨터구조") }

        #expect(subject.name == "컴구")
        #expect(recording.relativePath == "2026년 2학기/컴구/10-28 수 13-30.m4a")
        #expect(exists("2026년 2학기/컴구/10-28 수 13-30.m4a"))
        #expect(manager.subjects.map(\.name) == ["컴구"])
    }

    @Test func 녹음이_없는_과목은_이름만_바뀐다() throws {
        let subject = try makeSubject("컴구")

        try manager.rename(subject, to: "컴퓨터구조")

        #expect(subject.name == "컴퓨터구조")
        #expect(files.allPaths.isEmpty)
    }

    @Test func 폴더가_이미_없는_과목은_경로만_고친다() throws {
        let subject = try makeSubject("컴구")
        let recording = try addRecording("2026년 2학기/컴구/10-28 수 13-30.m4a", subject: subject, withFile: false)

        try manager.rename(subject, to: "컴퓨터구조")

        #expect(recording.relativePath == "2026년 2학기/컴퓨터구조/10-28 수 13-30.m4a")
        #expect(files.allPaths.isEmpty)
    }

    @Test func 녹음_중인_과목은_이름을_바꾸지_않는다() throws {
        let subject = try makeSubject("컴구")
        let recording = try addRecording("2026년 2학기/컴구/10-28 수 13-30.caf", subject: subject)
        manager.activePaths = { [recording.relativePath] }

        #expect(throws: SubjectError.recordingInProgress) { try manager.rename(subject, to: "컴퓨터구조") }

        #expect(subject.name == "컴구")
        #expect(exists("2026년 2학기/컴구/10-28 수 13-30.caf"))
    }

    @Test func 아직_저장되지_않은_녹음_중_파일이_폴더에_있어도_이름을_바꾸지_않는다() throws {
        let subject = try makeSubject("컴구")
        let finished = try addRecording("2026년 2학기/컴구/10-21 수 13-30.m4a", subject: subject)
        // 지금 녹음하는 파일은 정지 전이라 DB에 없다.
        let activePath = "2026년 2학기/컴구/10-28 수 13-30.caf"
        files.add(storage.url(for: activePath))
        manager.activePaths = { [activePath] }

        #expect(throws: SubjectError.recordingInProgress) { try manager.rename(subject, to: "컴퓨터구조") }

        #expect(subject.name == "컴구")
        #expect(finished.relativePath == "2026년 2학기/컴구/10-21 수 13-30.m4a")
        #expect(exists(activePath))
        #expect(exists(finished.relativePath))
    }

    @Test func 녹음이_하나도_저장되지_않은_과목도_녹음_중이면_이름을_바꾸지_않는다() throws {
        let subject = try makeSubject("컴구")
        let activePath = "2026년 2학기/컴구/10-28 수 13-30.caf"
        files.add(storage.url(for: activePath))
        manager.activePaths = { [activePath] }

        #expect(throws: SubjectError.recordingInProgress) { try manager.rename(subject, to: "컴퓨터구조") }

        #expect(subject.name == "컴구")
        #expect(exists(activePath))
    }

    @Test func 다른_과목을_녹음_중이면_이름을_바꿀_수_있다() throws {
        let subject = try makeSubject("컴구")
        let recording = try addRecording("2026년 2학기/컴구/10-21 수 13-30.m4a", subject: subject)
        manager.activePaths = { ["2026년 2학기/컴구2/10-28 수 13-30.caf"] }

        try manager.rename(subject, to: "컴퓨터구조")

        #expect(recording.relativePath == "2026년 2학기/컴퓨터구조/10-21 수 13-30.m4a")
    }

    @Test func 압축_전_파일이_남은_과목도_이름을_바꾸지_않는다() throws {
        let subject = try makeSubject("컴구")
        try addRecording("2026년 2학기/컴구/10-28 수 13-30.caf", subject: subject)

        #expect(throws: SubjectError.recordingInProgress) { try manager.rename(subject, to: "컴퓨터구조") }
        #expect(subject.name == "컴구")
    }

    @Test func 대소문자만_바꿔도_폴더가_따라간다() throws {
        let subject = try makeSubject("os")
        let recording = try addRecording("2026년 2학기/os/10-28 수 13-30.m4a", subject: subject)

        try manager.rename(subject, to: "OS")

        #expect(recording.relativePath == "2026년 2학기/OS/10-28 수 13-30.m4a")
        #expect(exists("2026년 2학기/OS/10-28 수 13-30.m4a"))
        #expect(files.allPaths.filter { $0.contains("/os/") }.isEmpty)
    }

    @Test func 이름을_바꾼_뒤_폴더_다시_읽기가_과목이나_녹음을_늘리지_않는다() async throws {
        let subject = try makeSubject("컴구")
        try addRecording("2026년 2학기/컴구/10-28 수 13-30.m4a", subject: subject)
        try manager.rename(subject, to: "컴퓨터구조")

        let rescanner = RecordingRescanner(context: context, storage: storage, durations: FakeDurationReader(), calendar: seoulCalendar)
        let report = try await rescanner.rescan()

        #expect(report.restored == 0)
        #expect(try context.fetch(FetchDescriptor<Subject>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<Recording>()).count == 1)
    }

    @Test func 다시_읽기로_되살린_녹음은_새_이름_과목에_붙는다() async throws {
        let subject = try makeSubject("컴구")
        try manager.rename(subject, to: "컴퓨터구조")
        let url = storage.url(for: "2026년 2학기/컴퓨터구조/11-04 수 13-30.m4a")
        files.add(url)
        files.sizes[url.standardizedFileURL.path] = 4_000_000

        let rescanner = RecordingRescanner(context: context, storage: storage, durations: FakeDurationReader(), calendar: seoulCalendar)
        _ = try await rescanner.rescan()

        #expect(try context.fetch(FetchDescriptor<Subject>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<Recording>()).first?.subject === subject)
    }
}
#endif
