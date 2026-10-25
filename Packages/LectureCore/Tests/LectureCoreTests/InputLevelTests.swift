import Foundation
import Testing
@testable import LectureCore

@Suite struct InputLevelTests {
    @Test func 데시벨을_0에서_1로_바꾼다() {
        #expect(InputLevel.normalize(decibels: 0) == 1)
        #expect(InputLevel.normalize(decibels: -60) == 0)
        #expect(InputLevel.normalize(decibels: -30) == 0.5)
    }

    @Test func 범위_밖과_숫자가_아닌_값은_끝으로_맞춘다() {
        #expect(InputLevel.normalize(decibels: -160) == 0)
        #expect(InputLevel.normalize(decibels: 6) == 1)
        #expect(InputLevel.normalize(decibels: -.infinity) == 0)
        #expect(InputLevel.normalize(decibels: .nan) == 0)
    }

    @Test func 무음_기준은_영하_50데시벨이다() {
        #expect(InputLevel.silenceThreshold == InputLevel.normalize(decibels: -50))
    }
}

@Suite struct SilenceDetectorTests {
    let start = date(2026, 3, 2, 10, 0)

    @Test func 정확히_10초까지는_경고하지_않고_넘으면_경고한다() {
        var detector = SilenceDetector()
        #expect(!detector.update(level: 0, at: start))
        #expect(!detector.update(level: 0, at: start.addingTimeInterval(10)))
        #expect(detector.update(level: 0, at: start.addingTimeInterval(10.1)))
    }

    @Test func 소리가_들어오면_처음부터_다시_센다() {
        var detector = SilenceDetector()
        _ = detector.update(level: 0, at: start)
        #expect(!detector.update(level: 0.5, at: start.addingTimeInterval(9)))
        #expect(!detector.update(level: 0, at: start.addingTimeInterval(15)))
        #expect(detector.update(level: 0, at: start.addingTimeInterval(25.5)))
        #expect(!detector.update(level: 0.5, at: start.addingTimeInterval(26)))
    }

    @Test func 기준과_같은_크기는_무음이_아니다() {
        var detector = SilenceDetector()
        _ = detector.update(level: InputLevel.silenceThreshold, at: start)
        #expect(!detector.update(level: InputLevel.silenceThreshold, at: start.addingTimeInterval(60)))
    }

    @Test func 초기화하면_세던_시간을_지운다() {
        var detector = SilenceDetector()
        _ = detector.update(level: 0, at: start)
        detector.reset()
        #expect(!detector.update(level: 0, at: start.addingTimeInterval(30)))
    }
}

#if canImport(SwiftData)
import SwiftData

@MainActor
@Suite struct RecordingControllerLevelTests {
    let container: ModelContainer
    let recorder = FakeAudioRecorder()
    let files = FakeFileStore()
    let clock = TestClock(date(2026, 3, 2, 10, 0))
    let controller: RecordingController

    init() throws {
        container = try LectureModelContainer.make(inMemory: true)
        let root = URL(filePath: "/tmp/LectureRecorderTests/Recordings", directoryHint: .isDirectory)
        let clock = clock
        controller = RecordingController(
            context: container.mainContext,
            recorder: recorder,
            storage: RecordingStorage(root: root, files: files),
            files: files,
            permission: FakeMicrophonePermission(status: .granted),
            storageCheckInterval: nil,
            levelCheckInterval: nil,
            calendar: seoulCalendar,
            now: { clock.now }
        )
    }

    @Test func 녹음_중_입력_크기를_따라간다() async throws {
        try await controller.start()
        recorder.inputLevel = 0.7
        controller.sampleInputLevel()
        #expect(controller.inputLevel == 0.7)
        #expect(!controller.isInputSilent)
    }

    @Test func 십_초_넘게_무음이면_경고하고_소리가_나면_사라진다() async throws {
        try await controller.start()
        recorder.inputLevel = 0
        controller.sampleInputLevel()
        clock.advance(by: 10)
        controller.sampleInputLevel()
        #expect(!controller.isInputSilent)
        clock.advance(by: 1)
        controller.sampleInputLevel()
        #expect(controller.isInputSilent)

        recorder.inputLevel = 0.4
        controller.sampleInputLevel()
        #expect(!controller.isInputSilent)
    }

    @Test func 일시정지_중에는_경고하지_않고_재개하면_다시_센다() async throws {
        try await controller.start()
        recorder.inputLevel = 0
        controller.sampleInputLevel()
        clock.advance(by: 8)
        try controller.pause()
        clock.advance(by: 60)
        controller.sampleInputLevel()
        #expect(!controller.isInputSilent)
        #expect(controller.inputLevel == 0)

        try controller.resume()
        controller.sampleInputLevel()
        clock.advance(by: 5)
        controller.sampleInputLevel()
        #expect(!controller.isInputSilent)
    }

    @Test func 정지하면_막대와_경고가_사라진다() async throws {
        try await controller.start()
        controller.sampleInputLevel()
        clock.advance(by: 30)
        controller.sampleInputLevel()
        #expect(controller.isInputSilent)
        try controller.stop()
        #expect(!controller.isInputSilent)
        #expect(controller.inputLevel == 0)
    }
}
#endif
