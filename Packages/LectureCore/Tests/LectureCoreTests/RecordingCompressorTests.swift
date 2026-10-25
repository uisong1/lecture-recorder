#if canImport(SwiftData)
import Foundation
import SwiftData
import Testing
@testable import LectureCore

@MainActor
@Suite struct RecordingCompressorTests {
    let container: ModelContainer
    let files = FakeFileStore()
    let converter: FakeAudioConverter
    let root = URL(filePath: "/tmp/LectureRecorderTests/Recordings", directoryHint: .isDirectory)

    init() throws {
        container = try LectureModelContainer.make(inMemory: true)
        converter = FakeAudioConverter(files: files)
    }

    var compressor: RecordingCompressor {
        RecordingCompressor(
            context: container.mainContext,
            storage: RecordingStorage(root: root, files: files),
            files: files,
            converter: converter
        )
    }

    @discardableResult
    func addRecording(_ path: String, createFile: Bool = true) throws -> Recording {
        let recording = Recording(title: path, subject: nil, startedAt: date(2026, 3, 2, 10, 0), duration: 10, relativePath: path)
        container.mainContext.insert(recording)
        try container.mainContext.save()
        if createFile { files.add(root.appending(path: path)) }
        return recording
    }

    @Test func CAF_녹음을_m4a로_바꾸고_CAF를_지운다() async throws {
        let recording = try addRecording("자료구조/a.caf")

        #expect(await compressor.compress(recording))

        #expect(recording.relativePath == "자료구조/a.m4a")
        #expect(recording.duration == FakeAudioConverter.duration)
        #expect(files.fileExists(at: root.appending(path: "자료구조/a.m4a")))
        #expect(!files.fileExists(at: root.appending(path: "자료구조/a.caf")))
        #expect(!files.fileExists(at: root.appending(path: "자료구조/a.converting.m4a")))
    }

    @Test func 압축하는_동안_다른_과목으로_옮겨도_옮긴_폴더에_m4a를_둔다() async throws {
        let other = try SubjectManager(context: container.mainContext).add(name: "선형대수", color: .blue)
        let recording = try addRecording("자료구조/a.caf")
        let manager = RecordingManager(context: container.mainContext, storage: RecordingStorage(root: root, files: files))
        converter.whileConverting = { try? manager.move(recording, to: other) }

        #expect(await compressor.compress(recording))

        #expect(recording.relativePath == "선형대수/a.m4a")
        #expect(files.fileExists(at: root.appending(path: "선형대수/a.m4a")))
        #expect(!files.fileExists(at: root.appending(path: "선형대수/a.caf")))
        #expect(!files.fileExists(at: root.appending(path: "자료구조/a.caf")))
        #expect(!files.fileExists(at: root.appending(path: "자료구조/a.converting.m4a")))
    }

    @Test func 변환에_실패하면_CAF와_경로를_그대로_둔다() async throws {
        converter.error = CocoaError(.fileWriteUnknown)
        let recording = try addRecording("자료구조/a.caf")

        #expect(await compressor.compress(recording) == false)

        #expect(recording.relativePath == "자료구조/a.caf")
        #expect(recording.duration == 10)
        #expect(files.fileExists(at: root.appending(path: "자료구조/a.caf")))
    }

    @Test func 파일이_없으면_건드리지_않는다() async throws {
        let recording = try addRecording("자료구조/a.caf", createFile: false)

        #expect(await compressor.compress(recording) == false)

        #expect(recording.relativePath == "자료구조/a.caf")
        #expect(converter.converted.isEmpty)
    }

    @Test func 이미_m4a면_아무것도_하지_않는다() async throws {
        let recording = try addRecording("자료구조/a.m4a")

        #expect(await compressor.compress(recording))

        #expect(recording.relativePath == "자료구조/a.m4a")
        #expect(converter.converted.isEmpty)
    }

    @Test func 변환은_끝났지만_저장_전에_꺼진_경우_다시_변환하지_않는다() async throws {
        let recording = try addRecording("자료구조/a.caf")
        files.add(root.appending(path: "자료구조/a.m4a"))

        #expect(await compressor.compress(recording))

        #expect(recording.relativePath == "자료구조/a.m4a")
        #expect(converter.converted.isEmpty)
        #expect(!files.fileExists(at: root.appending(path: "자료구조/a.caf")))
    }

    @Test func 남은_임시_파일은_지우고_다시_변환한다() async throws {
        let recording = try addRecording("자료구조/a.caf")
        files.add(root.appending(path: "자료구조/a.converting.m4a"))

        #expect(await compressor.compress(recording))

        #expect(recording.relativePath == "자료구조/a.m4a")
        #expect(!files.fileExists(at: root.appending(path: "자료구조/a.converting.m4a")))
    }

    @Test func 실행할_때_압축_안_된_녹음을_모두_압축한다() async throws {
        let first = try addRecording("자료구조/a.caf")
        let second = try addRecording("미분류/b.caf")
        let done = try addRecording("미분류/c.m4a")

        #expect(await compressor.compressPending() == 2)

        #expect(first.relativePath == "자료구조/a.m4a")
        #expect(second.relativePath == "미분류/b.m4a")
        #expect(done.relativePath == "미분류/c.m4a")
    }
}
#endif
