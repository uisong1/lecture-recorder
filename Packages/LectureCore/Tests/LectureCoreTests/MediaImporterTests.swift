#if canImport(SwiftData)
import Foundation
import SwiftData
import Testing
@testable import LectureCore

/// 변환 결과를 가짜 파일 시스템에 만들어 주는 가짜 소리 추출기.
final class FakeAudioExtractor: AudioExtracting, @unchecked Sendable {
    private let lock = NSLock()
    private var _error: Error?
    private var _extracted: [URL] = []
    private let files: FakeFileStore
    var duration: TimeInterval = 3600

    init(files: FakeFileStore) { self.files = files }

    var error: Error? {
        get { lock.withLock { _error } }
        set { lock.withLock { _error = newValue } }
    }
    var extracted: [URL] { lock.withLock { _extracted } }

    func extractAudio(from source: URL, to destination: URL) async throws -> TimeInterval {
        if let error { throw error }
        lock.withLock { _extracted.append(source) }
        files.add(destination)
        return duration
    }
}

@MainActor
@Suite struct MediaImporterTests {
    let container: ModelContainer
    let files = FakeFileStore()
    let storage: RecordingStorage
    let extractor: FakeAudioExtractor
    let directory: URL
    var context: ModelContext { container.mainContext }

    init() throws {
        container = try LectureModelContainer.make(inMemory: true)
        storage = RecordingStorage(root: URL(filePath: "/tmp/LectureRecorderTests/Recordings", directoryHint: .isDirectory), files: files)
        extractor = FakeAudioExtractor(files: files)
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func importer(durations: [String: TimeInterval] = [:]) -> MediaImporter {
        MediaImporter(context: context, storage: storage, files: files, extractor: extractor, durations: FakeDurationReader(durations: durations), calendar: seoulCalendar)
    }

    /// 앞부분이 mp4처럼 생긴 진짜 파일을 만들고, 가짜 파일 시스템에도 알린다.
    func makeSource(_ name: String, header: Data = MediaFileValidatorTests.mp4Header, size: Int64 = 1_000_000) throws -> URL {
        let url = directory.appending(path: name)
        try header.write(to: url)
        files.add(url)
        files.sizes[url.standardizedFileURL.path] = size
        return url
    }

    func subject(_ name: String = "자료구조", semester: String = "2026년 2학기") throws -> Subject {
        let subject = Subject(name: name, color: .blue)
        subject.semester = semester
        context.insert(subject)
        try context.save()
        return subject
    }

    @Test func mp4는_소리만_꺼내_과목_폴더에_저장한다() async throws {
        let source = try makeSource("screen.mp4")
        let subject = try subject()

        let recording = try await importer().importFile(at: source, subject: subject, startedAt: date(2026, 10, 28, 13, 30))

        #expect(recording.relativePath == "2026년 2학기/자료구조/10-28 수 13-30.m4a")
        #expect(recording.duration == 3600)
        #expect(recording.subject === subject)
        #expect(recording.title == "자료구조 10월 28일 13:30")
        #expect(extractor.extracted == [source])
        #expect(files.fileExists(at: storage.url(for: recording.relativePath)))
        // 임시 파일은 남지 않고, 원본은 그대로다.
        #expect(!files.fileExists(at: storage.url(for: "2026년 2학기/자료구조/10-28 수 13-30.converting.m4a")))
        #expect(files.fileExists(at: source))
        #expect(try context.fetch(FetchDescriptor<Recording>()).count == 1)
    }

    @Test func m4a는_추출하지_않고_복사한다() async throws {
        let source = try makeSource("lecture.m4a")

        let recording = try await importer(durations: ["10-28 수 13-30.converting.m4a": 90]).importFile(at: source, subject: nil, startedAt: date(2026, 10, 28, 13, 30), title: "보강 수업")

        #expect(extractor.extracted.isEmpty)
        #expect(recording.title == "보강 수업")
        #expect(recording.subject == nil)
        #expect(recording.duration == 90)
        #expect(recording.relativePath.hasPrefix("미분류/"))
        #expect(files.fileExists(at: storage.url(for: recording.relativePath)))
    }

    @Test func 지원하지_않는_확장자는_거부한다() async throws {
        let source = try makeSource("notes.txt")

        await #expect(throws: MediaImportError.unsupportedType("notes.txt")) {
            try await importer().importFile(at: source, subject: nil, startedAt: date(2026, 10, 28, 13, 30))
        }
        #expect(try context.fetch(FetchDescriptor<Recording>()).isEmpty)
    }

    @Test func ftyp가_없는_파일은_받다_만_파일로_보고_거부한다() async throws {
        let source = try makeSource("screen.mp4", header: Data("<html>403</html>".utf8))

        await #expect(throws: MediaImportError.notMediaFile("screen.mp4")) {
            try await importer().importFile(at: source, subject: nil, startedAt: date(2026, 10, 28, 13, 30))
        }
        #expect(extractor.extracted.isEmpty)
        #expect(try context.fetch(FetchDescriptor<Recording>()).isEmpty)
    }

    @Test func 소리가_없는_영상은_실패하고_파일을_남기지_않는다() async throws {
        let source = try makeSource("screen.mp4")
        extractor.error = MediaImportError.noAudio("screen.mp4")

        await #expect(throws: MediaImportError.noAudio("screen.mp4")) {
            try await importer().importFile(at: source, subject: nil, startedAt: date(2026, 10, 28, 13, 30))
        }
        #expect(try context.fetch(FetchDescriptor<Recording>()).isEmpty)
        #expect(!files.allPaths.contains { $0.contains("미분류") && $0.hasSuffix(".m4a") })
    }

    @Test func 길이를_읽지_못하는_m4a는_복사본을_지우고_실패한다() async throws {
        let source = try makeSource("broken.m4a")

        await #expect(throws: MediaImportError.unplayable("broken.m4a")) {
            try await importer().importFile(at: source, subject: nil, startedAt: date(2026, 10, 28, 13, 30))
        }
        #expect(!files.allPaths.contains { $0.hasSuffix(".m4a") && $0.contains("Recordings") })
        #expect(try context.fetch(FetchDescriptor<Recording>()).isEmpty)
    }

    @Test func 저장_공간이_모자라면_가져오지_않는다() async throws {
        let source = try makeSource("screen.mp4", size: 1_000_000)
        files.capacity = 1_000_000 + MediaImporter.spareBytes - 1

        await #expect(throws: MediaImportError.notEnoughSpace) {
            try await importer().importFile(at: source, subject: nil, startedAt: date(2026, 10, 28, 13, 30))
        }
        #expect(extractor.extracted.isEmpty)
    }

    @Test func 같은_시각에_두_번_가져오면_이름에_번호를_붙인다() async throws {
        let source = try makeSource("screen.mp4")
        let importer = importer()

        let first = try await importer.importFile(at: source, subject: nil, startedAt: date(2026, 10, 28, 13, 30))
        let second = try await importer.importFile(at: source, subject: nil, startedAt: date(2026, 10, 28, 13, 30))

        #expect(first.relativePath != second.relativePath)
        #expect(second.relativePath.hasSuffix("_2.m4a"))
    }
}

@MainActor
@Suite struct MediaImportModelTests {
    let container: ModelContainer
    let files = FakeFileStore()
    let extractor: FakeAudioExtractor
    let directory: URL
    let model: MediaImportModel
    let target: Subject
    var context: ModelContext { container.mainContext }

    init() throws {
        container = try LectureModelContainer.make(inMemory: true)
        let storage = RecordingStorage(root: URL(filePath: "/tmp/LectureRecorderTests/Recordings", directoryHint: .isDirectory), files: files)
        extractor = FakeAudioExtractor(files: files)
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let importer = MediaImporter(context: container.mainContext, storage: storage, files: files, extractor: extractor, durations: FakeDurationReader(), calendar: seoulCalendar)
        let subject = Subject(name: "운영체제", color: .blue)
        container.mainContext.insert(subject)
        target = subject
        model = MediaImportModel(
            importer: importer,
            suggestSubject: { _ in subject },
            suggestDate: { _ in date(2026, 10, 28, 9, 0) },
            now: { date(2026, 11, 1, 0, 0) }
        )
    }

    func makeSource(_ name: String, header: Data = MediaFileValidatorTests.mp4Header) throws -> URL {
        let url = directory.appending(path: name)
        try header.write(to: url)
        files.add(url)
        files.sizes[url.standardizedFileURL.path] = 1_000
        return url
    }

    @Test func 놓은_파일에서_날짜와_과목을_추천한다() throws {
        model.begin(urls: [try makeSource("a.mp4")])

        #expect(model.isPresented)
        #expect(model.items.map(\.startedAt) == [date(2026, 10, 28, 9, 0)])
        #expect(model.subject === target)
    }

    @Test func mp4_m4a가_아닌_파일은_빼고_알린다() throws {
        model.begin(urls: [try makeSource("a.mp4"), try makeSource("b.pdf")])

        #expect(model.items.map(\.name) == ["a.mp4"])
        #expect(model.message?.contains("b.pdf") == true)
    }

    @Test func 가져오면_목록에_저장되고_창이_닫힌다() async throws {
        model.begin(urls: [try makeSource("a.mp4"), try makeSource("b.mp4")])

        await model.run()

        #expect(try context.fetch(FetchDescriptor<Recording>()).count == 2)
        #expect(!model.isPresented)
        #expect(model.items.isEmpty)
    }

    @Test func 한_파일이_실패해도_나머지는_가져오고_실패한_파일을_알린다() async throws {
        model.begin(urls: [try makeSource("bad.mp4", header: Data("oops".utf8)), try makeSource("good.mp4")])

        await model.run()

        #expect(try context.fetch(FetchDescriptor<Recording>()).count == 1)
        #expect(model.isPresented)
        #expect(model.message?.contains("bad.mp4") == true)
        #expect(model.items.map(\.status).contains(.done))
        #expect(model.canImport)
    }

    @Test func 날짜를_고치면_그_날짜로_저장한다() async throws {
        model.begin(urls: [try makeSource("a.mp4")])
        model.setDate(date(2026, 10, 30, 15, 0), for: model.items[0].id)

        await model.run()

        let recordings = try context.fetch(FetchDescriptor<Recording>())
        #expect(recordings.map(\.startedAt) == [date(2026, 10, 30, 15, 0)])
    }
}
#endif
