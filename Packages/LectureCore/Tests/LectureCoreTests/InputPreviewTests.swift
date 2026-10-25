import Foundation
import Testing
@testable import LectureCore

#if canImport(SwiftData)
import SwiftData

@MainActor
final class FakeLevelPreview: AudioLevelPreviewing {
    var level: Float = 0
    var startError: Error?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var isOn = false

    func start() throws {
        if let startError { throw startError }
        startCount += 1
        isOn = true
    }

    func stop() {
        stopCount += 1
        isOn = false
    }
}

@MainActor
@Suite struct InputPreviewTests {
    let container: ModelContainer
    let preview = FakeLevelPreview()
    let clock = TestClock(date(2026, 3, 2, 10, 0))
    let permission: FakeMicrophonePermission

    init() throws {
        container = try LectureModelContainer.make(inMemory: true)
        permission = FakeMicrophonePermission(status: .granted)
    }

    func makeController(status: MicrophonePermissionStatus = .granted) -> RecordingController {
        permission.status = status
        let root = URL(filePath: "/tmp/LectureRecorderTests/Recordings", directoryHint: .isDirectory)
        let files = FakeFileStore()
        let clock = clock
        return RecordingController(
            context: container.mainContext,
            recorder: FakeAudioRecorder(),
            storage: RecordingStorage(root: root, files: files),
            files: files,
            permission: permission,
            levelPreview: preview,
            storageCheckInterval: nil,
            levelCheckInterval: nil,
            calendar: seoulCalendar,
            now: { clock.now }
        )
    }

    @Test func 권한이_있으면_확인이_켜지고_입력_크기를_따라간다() async {
        let controller = makeController()
        await controller.startPreview()
        #expect(controller.isPreviewing)
        preview.level = 0.6
        controller.samplePreviewLevel()
        #expect(controller.previewLevel == 0.6)
        #expect(controller.previewOutcome == nil)
    }

    @Test func 오_초_뒤에_스스로_끝나고_소리가_있었으면_들림으로_본다() async {
        let controller = makeController()
        await controller.startPreview()
        preview.level = 0.5
        clock.advance(by: 2)
        controller.samplePreviewLevel()
        preview.level = 0
        clock.advance(by: 2.9)
        controller.samplePreviewLevel()
        #expect(controller.isPreviewing)
        clock.advance(by: 0.1)
        controller.samplePreviewLevel()
        #expect(!controller.isPreviewing)
        #expect(!preview.isOn)
        #expect(controller.previewOutcome == .heard)
        #expect(controller.previewLevel == 0)
    }

    @Test func 오_초_내내_무음이면_조용함으로_본다() async {
        let controller = makeController()
        await controller.startPreview()
        preview.level = InputLevel.silenceThreshold - 0.01
        clock.advance(by: 5)
        controller.samplePreviewLevel()
        #expect(controller.previewOutcome == .quiet)
    }

    @Test func 무음_기준과_같은_크기는_소리로_본다() async {
        let controller = makeController()
        await controller.startPreview()
        preview.level = InputLevel.silenceThreshold
        controller.samplePreviewLevel()
        clock.advance(by: 5)
        controller.samplePreviewLevel()
        #expect(controller.previewOutcome == .heard)
    }

    @Test func 권한을_아직_안_물었으면_확인을_누를_때_묻는다() async {
        let controller = makeController(status: .notDetermined)
        await controller.startPreview()
        #expect(permission.requestCount == 1)
        #expect(controller.isPreviewing)
    }

    @Test func 권한이_거부됐으면_켜지_않는다() async {
        let controller = makeController(status: .denied)
        await controller.startPreview()
        #expect(!controller.isPreviewing)
        #expect(preview.startCount == 0)
        #expect(controller.isPermissionDenied)
    }

    @Test func 켜지_못하면_오류_문구를_남기고_녹음에는_영향이_없다() async {
        preview.startError = CocoaError(.fileReadUnknown)
        let controller = makeController()
        await controller.startPreview()
        #expect(!controller.isPreviewing)
        #expect(controller.errorMessage != nil)
        controller.errorMessage = nil
        preview.startError = nil
        try? await controller.start()
        #expect(controller.isRecording)
    }

    @Test func 확인_중에_두_번_눌러도_한_번만_시작한다() async {
        let controller = makeController()
        await controller.startPreview()
        await controller.startPreview()
        #expect(preview.startCount == 1)
    }

    @Test func 확인_중_녹음을_시작하면_확인이_즉시_끝나고_결과는_없다() async throws {
        let controller = makeController()
        await controller.startPreview()
        preview.level = 0.5
        controller.samplePreviewLevel()
        try await controller.start()
        #expect(!controller.isPreviewing)
        #expect(!preview.isOn)
        #expect(controller.previewOutcome == nil)
        await controller.startPreview()
        #expect(!controller.isPreviewing)
    }

    @Test func 화면을_떠나_멈추면_결과를_남기지_않는다() async {
        let controller = makeController()
        await controller.startPreview()
        controller.stopPreview()
        #expect(!controller.isPreviewing)
        #expect(!preview.isOn)
        #expect(controller.previewOutcome == nil)
    }
}
#endif
