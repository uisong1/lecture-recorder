#if canImport(SwiftData)
import Foundation
import SwiftData
import Testing
@testable import LectureCore

@MainActor
final class ResultBox {
    var value: Bool?
}

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
        other.semester = "2026년 2학기"
        let manager = RecordingManager(context: container.mainContext, storage: RecordingStorage(root: root, files: files))
        converter.whileConverting = { try? manager.move(recording, to: other) }

        #expect(await compressor.compress(recording))

        #expect(recording.relativePath == "2026년 2학기/선형대수/a.m4a")
        #expect(files.fileExists(at: root.appending(path: "2026년 2학기/선형대수/a.m4a")))
        #expect(!files.fileExists(at: root.appending(path: "2026년 2학기/선형대수/a.caf")))
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

    @Test func 변환하는_동안_녹음을_지웠으면_결과_파일을_남기지_않는다() async throws {
        let recording = try addRecording("자료구조/a.caf")
        let manager = RecordingManager(context: container.mainContext, storage: RecordingStorage(root: root, files: files))
        converter.whileConverting = { try? manager.delete(recording) }

        #expect(await compressor.compress(recording) == false)

        #expect(try container.mainContext.fetchCount(FetchDescriptor<Recording>()) == 0)
        #expect(!files.fileExists(at: root.appending(path: "자료구조/a.m4a")))
        #expect(!files.fileExists(at: root.appending(path: "자료구조/a.converting.m4a")))
        #expect(!files.fileExists(at: root.appending(path: "자료구조/a.caf")))
    }

    @Test func 이미_지워진_녹음은_변환하지_않는다() async throws {
        let recording = try addRecording("자료구조/a.caf")
        container.mainContext.delete(recording)
        try container.mainContext.save()

        #expect(await compressor.compress(recording) == false)

        #expect(converter.converted.isEmpty)
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

    @Test func 미리_있던_m4a가_원본보다_짧으면_믿지_않고_다시_압축한다() async throws {
        let recording = try addRecording("자료구조/a.caf")
        let leftover = root.appending(path: "자료구조/a.m4a")
        files.add(leftover)
        converter.durations[root.appending(path: "자료구조/a.caf").standardizedFileURL] = 5400
        converter.durations[leftover.standardizedFileURL] = 600
        let compressor = compressor
        converter.whileConverting = {
            // 새 압축본이 준비되기 전에는 옛 m4a도 CAF도 그대로 있어야 한다.
            #expect(files.fileExists(at: root.appending(path: "자료구조/a.caf")))
        }

        #expect(await compressor.compress(recording))

        #expect(converter.converted.map(\.lastPathComponent) == ["a.caf"])
        #expect(recording.relativePath == "자료구조/a.m4a")
        #expect(recording.duration == FakeAudioConverter.duration)
        #expect(files.fileExists(at: leftover))
        #expect(!files.fileExists(at: root.appending(path: "자료구조/a.converting.m4a")))
        #expect(!files.fileExists(at: root.appending(path: "자료구조/a.caf")))
    }

    @Test func 짧은_m4a가_있고_다시_압축도_실패하면_CAF를_지우지_않는다() async throws {
        let recording = try addRecording("자료구조/a.caf")
        let leftover = root.appending(path: "자료구조/a.m4a")
        files.add(leftover)
        converter.durations[root.appending(path: "자료구조/a.caf").standardizedFileURL] = 5400
        converter.durations[leftover.standardizedFileURL] = 600
        converter.error = CocoaError(.fileWriteUnknown)

        #expect(await compressor.compress(recording) == false)

        #expect(recording.relativePath == "자료구조/a.caf")
        #expect(recording.duration == 10)
        #expect(files.fileExists(at: root.appending(path: "자료구조/a.caf")))
    }

    @Test func 미리_있던_m4a를_읽을_수_없으면_다시_압축한다() async throws {
        // 끝 정보를 쓰기 전에 꺼진 m4a는 열리지 않는다.
        let recording = try addRecording("자료구조/a.caf")
        let leftover = root.appending(path: "자료구조/a.m4a")
        files.add(leftover)
        converter.unreadable = [leftover.standardizedFileURL]

        #expect(await compressor.compress(recording))

        #expect(converter.converted.map(\.lastPathComponent) == ["a.caf"])
        #expect(recording.relativePath == "자료구조/a.m4a")
        #expect(!files.fileExists(at: root.appending(path: "자료구조/a.caf")))
    }

    @Test func 압축하는_동안_폴더째_옮겨져도_임시_파일을_새_폴더에서_찾아_옮긴다() async throws {
        let recording = try addRecording("자료구조/a.caf")
        let storage = RecordingStorage(root: root, files: files)
        converter.whileConverting = {
            // 폴더 이동은 임시 파일(.converting.m4a)도 함께 옮긴다.
            try? storage.moveFolder(from: "자료구조", to: "자료구조론")
            recording.relativePath = "자료구조론/a.caf"
        }

        #expect(await compressor.compress(recording))

        #expect(recording.relativePath == "자료구조론/a.m4a")
        #expect(files.fileExists(at: root.appending(path: "자료구조론/a.m4a")))
        #expect(!files.fileExists(at: root.appending(path: "자료구조론/a.caf")))
        #expect(!files.fileExists(at: root.appending(path: "자료구조론/a.converting.m4a")))
        #expect(!files.fileExists(at: root.appending(path: "자료구조/a.converting.m4a")))
    }

    @Test func 같은_녹음을_동시에_두_번_압축하지_않는다() async throws {
        let recording = try addRecording("자료구조/a.caf")
        let compressor = compressor
        let second = ResultBox()
        converter.onStart = {
            // 앱 시작 압축이 도는 중에 정지 직후 압축이 같은 녹음을 다시 집은 경우.
            second.value = await compressor.compress(recording)
        }

        #expect(await compressor.compress(recording))

        #expect(second.value == false)
        #expect(converter.converted.count == 1)
        #expect(recording.relativePath == "자료구조/a.m4a")
        #expect(files.fileExists(at: root.appending(path: "자료구조/a.m4a")))
    }

    @Test func 압축이_끝나면_같은_녹음을_다시_압축할_수_있다() async throws {
        converter.error = CocoaError(.fileWriteUnknown)
        let recording = try addRecording("자료구조/a.caf")
        let compressor = compressor
        #expect(await compressor.compress(recording) == false)

        converter.error = nil
        #expect(await compressor.compress(recording))
        #expect(recording.relativePath == "자료구조/a.m4a")
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
