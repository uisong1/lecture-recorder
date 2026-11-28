import Foundation
import Testing
@testable import LectureCore

#if canImport(SwiftData)
@MainActor
@Suite struct PlaybackPanelVisibilityTests {
    let player = FakeAudioPlayer()
    let root = URL(filePath: "/tmp/LectureRecorderTests/Recordings", directoryHint: .isDirectory)

    func makeController() -> PlaybackController {
        let defaults = UserDefaults(suiteName: "PlaybackPanelTests-\(UUID().uuidString)") ?? .standard
        return PlaybackController(
            player: player,
            storage: RecordingStorage(root: root, files: FakeFileStore()),
            defaults: defaults,
            isRecording: { false },
            outputInspector: nil
        )
    }

    func makeRecording() -> Recording {
        Recording(title: "녹음", subject: nil, startedAt: date(2026, 3, 2, 10, 0), duration: 60, relativePath: "자료구조/2026-03-02_1000.m4a")
    }

    @Test func 패널을_닫으면_재생이_멈추고_녹음은_그대로() {
        let controller = makeController()
        let recording = makeRecording()
        controller.select(recording)
        controller.play()
        #expect(controller.isPlaying)
        controller.closePanel()
        #expect(controller.isPanelHidden)
        #expect(!controller.isPlaying)
        #expect(controller.current === recording)
    }

    @Test func 닫은_뒤_재생하면_패널이_다시_보인다() {
        let controller = makeController()
        controller.select(makeRecording())
        controller.closePanel()
        controller.play()
        #expect(!controller.isPanelHidden)
    }

    @Test func 닫은_뒤_같은_녹음을_다시_고르면_다시_보인다() {
        let controller = makeController()
        let recording = makeRecording()
        controller.select(recording)
        controller.closePanel()
        controller.select(recording)
        #expect(!controller.isPanelHidden)
    }
}
#endif
