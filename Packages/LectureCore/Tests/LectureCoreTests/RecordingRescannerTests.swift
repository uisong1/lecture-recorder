#if canImport(SwiftData)
import Foundation
import SwiftData
import Testing
@testable import LectureCore

struct FakeDurationReader: AudioDurationReading {
    var durations: [String: TimeInterval] = [:]
    func duration(of url: URL) async -> TimeInterval? { durations[url.lastPathComponent] }
}

@MainActor
@Suite struct RecordingRescannerTests {
    let container: ModelContainer
    let files = FakeFileStore()
    let storage: RecordingStorage
    var context: ModelContext { container.mainContext }

    init() throws {
        container = try LectureModelContainer.make(inMemory: true)
        storage = RecordingStorage(root: URL(filePath: "/tmp/LectureRecorderTests/Recordings", directoryHint: .isDirectory), files: files)
    }

    func rescanner(_ durations: [String: TimeInterval] = [:]) -> RecordingRescanner {
        RecordingRescanner(context: context, storage: storage, durations: FakeDurationReader(durations: durations), calendar: seoulCalendar)
    }

    func addFile(_ path: String, size: Int64 = 4_000_000, modified: Date? = nil) {
        let url = storage.url(for: path)
        files.add(url)
        files.sizes[url.standardizedFileURL.path] = size
        if let modified { files.modificationDates[url.standardizedFileURL.path] = modified }
    }

    func all() throws -> [Recording] { try context.fetch(FetchDescriptor<Recording>()) }

    @Test func 목록에_있는_파일은_건너뛴다() async throws {
        addFile("2026년 2학기/컴퓨터구조/10-28 수 13-30.m4a")
        context.insert(Recording(title: "녹음", subject: nil, startedAt: date(2026, 10, 28, 13, 30), duration: 60, relativePath: "2026년 2학기/컴퓨터구조/10-28 수 13-30.m4a"))
        try context.save()

        let report = try await rescanner().rescan()

        #expect(report.restored == 0)
        #expect(try all().count == 1)
    }

    @Test func 폴더_이름으로_과목을_찾고_파일_이름에서_시간을_읽는다() async throws {
        let cs = Subject(name: "컴퓨터구조")
        cs.semester = "2026년 2학기"
        context.insert(cs)
        addFile("2026년 2학기/컴퓨터구조/10-28 수 13-30.m4a")

        let report = try await rescanner(["10-28 수 13-30.m4a": 3_000]).rescan()

        #expect(report.restored == 1)
        let recording = try #require(try all().first)
        #expect(recording.subject?.name == "컴퓨터구조")
        #expect(recording.startedAt == date(2026, 10, 28, 13, 30))
        #expect(recording.duration == 3_000)
        #expect(recording.relativePath == "2026년 2학기/컴퓨터구조/10-28 수 13-30.m4a")
    }

    @Test func 맞는_과목이_없으면_미분류로_되살린다() async throws {
        addFile("2026년 2학기/없는과목/10-28 수 13-30.m4a")
        addFile("미분류/2026-03-02_1000.m4a")

        let report = try await rescanner().rescan()

        #expect(report.restored == 2)
        #expect(try all().allSatisfy { $0.subject == nil })
    }

    @Test func 이름_규칙이_깨졌으면_수정_시각과_파일_이름을_쓴다() async throws {
        let modified = date(2026, 9, 1, 9, 15)
        addFile("미분류/강의 녹음.m4a", modified: modified)

        _ = try await rescanner().rescan()

        let recording = try #require(try all().first)
        #expect(recording.title == "강의 녹음")
        #expect(recording.startedAt == modified)
    }

    @Test func 길이를_읽지_못하면_크기로_어림하고_알린다() async throws {
        addFile("미분류/강의 녹음.m4a", size: 1_000_000)

        let report = try await rescanner().rescan()

        #expect(report.estimatedLength == 1)
        let recording = try #require(try all().first)
        #expect(recording.duration > 0)
        #expect(report.summary.contains("어림"))
    }

    @Test func 두_번_실행해도_중복되지_않는다() async throws {
        addFile("미분류/a.m4a")
        addFile("미분류/b.m4a")

        let first = try await rescanner().rescan()
        let second = try await rescanner().rescan()

        #expect(first.restored == 2)
        #expect(second.restored == 0)
        #expect(try all().count == 2)
    }

    @Test func 변환_중_임시_파일은_무시한다() async throws {
        addFile("미분류/10-28 수 13-30.converting.m4a")

        let report = try await rescanner().rescan()

        #expect(report.restored == 0)
        #expect(try all().isEmpty)
    }

    @Test func 빈_파일은_열_수_없음으로_센다() async throws {
        addFile("미분류/a.m4a", size: 0)

        let report = try await rescanner().rescan()

        #expect(report.restored == 0)
        #expect(report.unreadable == 1)
        #expect(report.summary.contains("열 수 없어"))
    }

    @Test func 같은_이름의_caf와_m4a는_m4a_하나만_되살린다() async throws {
        addFile("미분류/10-28 수 13-30.caf")
        addFile("미분류/10-28 수 13-30.m4a")

        let report = try await rescanner().rescan()

        #expect(report.restored == 1)
        #expect(try all().first?.relativePath == "미분류/10-28 수 13-30.m4a")
    }

    @Test func 한쪽이_이미_목록에_있으면_같은_이름의_짝은_건너뛴다() async throws {
        addFile("미분류/10-28 수 13-30.caf")
        addFile("미분류/10-28 수 13-30.m4a")
        context.insert(Recording(title: "녹음", subject: nil, startedAt: date(2026, 10, 28, 13, 30), duration: 60, relativePath: "미분류/10-28 수 13-30.caf"))
        try context.save()

        let report = try await rescanner().rescan()

        #expect(report.restored == 0)
    }

    @Test func 지금_녹음_중인_파일은_건드리지_않는다() async throws {
        addFile("미분류/10-28 수 13-30.caf")

        let report = try await rescanner().rescan(skipping: ["미분류/10-28 수 13-30.caf"])

        #expect(report.restored == 0)
    }

    @Test func 되살리기와_함께_빈_폴더를_정리하고_파일은_그대로_둔다() async throws {
        let root = storage.root
        try files.createDirectory(at: root.appending(path: "예전과목"))
        addFile("미분류/a.m4a")

        let report = try await rescanner().rescan()

        #expect(report.removedEmptyFolders == 1)
        #expect(!files.isDirectory(at: root.appending(path: "예전과목")))
        #expect(files.fileExists(at: storage.url(for: "미분류/a.m4a")))
    }

    @Test func 같은_이름_과목은_학기_폴더까지_맞는_쪽을_쓴다() async throws {
        let old = Subject(name: "선형대수")
        old.semester = "2026년 1학기"
        let new = Subject(name: "선형대수")
        new.semester = "2026년 2학기"
        context.insert(old)
        context.insert(new)
        addFile("2026년 1학기/선형대수/03-02 월 10-00.m4a")

        _ = try await rescanner().rescan()

        #expect(try all().first?.subject === old)
    }

    @Test func 요약_문구() {
        #expect(RescanReport().summary == "목록에 없는 녹음 파일이 없습니다.")
        #expect(RescanReport(restored: 3, unreadable: 1).summary == "3개를 목록에 되살렸습니다. 1개는 열 수 없어 건너뛰었습니다.")
    }
}
#endif
