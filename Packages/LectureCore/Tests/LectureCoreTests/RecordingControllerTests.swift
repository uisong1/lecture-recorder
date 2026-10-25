#if canImport(SwiftData)
import Foundation
import SwiftData
import Testing
@testable import LectureCore

@MainActor
@Suite struct RecordingControllerTests {
    let container: ModelContainer
    let recorder = FakeAudioRecorder()
    let files = FakeFileStore()
    let permission = FakeMicrophonePermission(status: .granted)
    let root = URL(filePath: "/tmp/LectureRecorderTests/Recordings", directoryHint: .isDirectory)
    var clock = date(2026, 3, 2, 10, 0)

    init() throws {
        container = try LectureModelContainer.make(inMemory: true)
    }

    func makeController(at time: Date) -> RecordingController {
        RecordingController(
            context: container.mainContext,
            recorder: recorder,
            storage: RecordingStorage(root: root, files: files),
            files: files,
            permission: permission,
            calendar: seoulCalendar,
            now: { time }
        )
    }

    func addSubjectWithSlot() throws -> Subject {
        let subjects = SubjectManager(context: container.mainContext)
        let subject = try subjects.add(name: "자료구조", color: .green)
        try ScheduleManager(context: container.mainContext)
            .add(subject: subject, weekday: .monday, start: TimeOfDay(hour: 10), end: TimeOfDay(hour: 11, minute: 15))
        return subject
    }

    @Test func 시작하고_정지하면_Recording이_저장된다() async throws {
        let subject = try addSubjectWithSlot()
        let controller = makeController(at: date(2026, 3, 2, 10, 0))

        try await controller.start()
        #expect(controller.isRecording)
        #expect(controller.currentSubjectName == "자료구조")
        #expect(recorder.startedURLs.map(\.path) == ["/tmp/LectureRecorderTests/Recordings/자료구조/2026-03-02_1000.m4a"])

        recorder.currentTime = 4_500
        let saved = try controller.stop()

        #expect(!controller.isRecording)
        let recordings = try container.mainContext.fetch(FetchDescriptor<Recording>())
        #expect(recordings.count == 1)
        let recording = try #require(recordings.first)
        #expect(recording === saved)
        #expect(recording.subject === subject)
        #expect(recording.title == "자료구조 3월 2일 10:00")
        #expect(recording.duration == 4_500)
        #expect(recording.startedAt == date(2026, 3, 2, 10, 0))
        #expect(recording.relativePath == "자료구조/2026-03-02_1000.m4a")
    }

    @Test func 수업_없는_시간이면_미분류로_저장된다() async throws {
        _ = try addSubjectWithSlot()
        let controller = makeController(at: date(2026, 3, 2, 12, 30))
        try await controller.start()
        #expect(controller.currentSubjectName == "미분류")
        let recording = try controller.stop()
        #expect(recording.subject == nil)
        #expect(recording.relativePath == "미분류/2026-03-02_1230.m4a")
    }

    @Test func 권한이_없으면_시작하지_않는다() async throws {
        permission.status = .denied
        let controller = makeController(at: clock)
        await #expect(throws: RecordingError.permissionDenied) { try await controller.start() }
        #expect(!controller.isRecording)
        #expect(recorder.startedURLs.isEmpty)
    }

    @Test func 저장_공간이_부족하면_시작하지_않는다() async throws {
        files.capacity = 10 * 1024 * 1024
        let controller = makeController(at: clock)
        await #expect(throws: RecordingError.insufficientStorage) { try await controller.start() }
        #expect(recorder.startedURLs.isEmpty)
    }

    @Test func 녹음기가_실패하면_오류를_알린다() async throws {
        recorder.startError = CocoaError(.fileWriteNoPermission)
        let controller = makeController(at: clock)
        await controller.toggle()
        #expect(!controller.isRecording)
        #expect(controller.errorMessage?.hasPrefix("녹음을 시작하지 못했습니다") == true)
    }

    @Test func 녹음_중이_아니면_정지할_수_없다() {
        let controller = makeController(at: clock)
        #expect(throws: RecordingError.notRecording) { try controller.stop() }
    }

    @Test func 버튼으로_시작과_정지를_번갈아_한다() async throws {
        let controller = makeController(at: clock)
        await controller.toggle()
        #expect(controller.isRecording)
        await controller.toggle()
        #expect(!controller.isRecording)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Recording>()) == 1)
    }

    @Test func 같은_분에_두_번_녹음하면_파일_이름이_겹치지_않는다() async throws {
        let controller = makeController(at: clock)
        try await controller.start()
        files.add(recorder.startedURLs[0])
        try controller.stop()
        try await controller.start()
        let second = try controller.stop()
        #expect(second.relativePath == "미분류/2026-03-02_1000_2.m4a")
    }
}

@Suite struct ElapsedFormatTests {
    @Test(arguments: [(0.0, "00:00"), (5.9, "00:05"), (65, "01:05"), (600, "10:00"), (5_403, "90:03"), (-3, "00:00")])
    func 경과_시간을_분과_초로_보여준다(seconds: Double, expected: String) {
        #expect(RecordingController.format(seconds) == expected)
    }
}
#endif
