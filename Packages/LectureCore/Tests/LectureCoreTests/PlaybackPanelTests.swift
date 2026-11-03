import Foundation
import Testing
@testable import LectureCore

@Suite struct PlaybackPanelLayoutTests {
    @Test func 범위_안이면_그대로() {
        #expect(PlaybackPanelLayout.clamp(300) == 300)
    }

    @Test func 너무_작거나_크면_범위로_맞춘다() {
        #expect(PlaybackPanelLayout.clamp(10) == PlaybackPanelLayout.minHeight)
        #expect(PlaybackPanelLayout.clamp(5000) == PlaybackPanelLayout.maxHeight)
    }

    @Test func 창이_낮으면_위_영역을_남긴다() {
        #expect(PlaybackPanelLayout.clamp(500, available: 500) == 340)
        #expect(PlaybackPanelLayout.clamp(500, available: 100) == PlaybackPanelLayout.minHeight)
    }

    @Test func 위로_끌면_커지고_아래로_끌면_작아진다() {
        #expect(PlaybackPanelLayout.height(start: 300, dragUp: 50) == 350)
        #expect(PlaybackPanelLayout.height(start: 300, dragUp: -100) == 200)
    }
}

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
