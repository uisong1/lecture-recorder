import Foundation
import Testing
@testable import LectureCore

@Suite struct RecordingPlaybackGuardTests {
    @Test func 녹음_중_스피커면_확인이_필요하다() {
        #expect(RecordingPlaybackGuard.needsConfirmation(isRecording: true, output: .builtInSpeaker))
    }

    @Test func 녹음_중_이어폰이면_바로_재생한다() {
        #expect(!RecordingPlaybackGuard.needsConfirmation(isRecording: true, output: .external))
    }

    @Test func 녹음_중이_아니면_바로_재생한다() {
        for output in [AudioOutputKind.builtInSpeaker, .external, .unknown] {
            #expect(!RecordingPlaybackGuard.needsConfirmation(isRecording: false, output: output))
        }
    }

    @Test func 출력_장치를_모르면_확인이_필요하다() {
        #expect(RecordingPlaybackGuard.needsConfirmation(isRecording: true, output: .unknown))
    }
}

#if canImport(SwiftData)
@MainActor
@Suite struct PlaybackDuringRecordingTests {
    let player = FakeAudioPlayer()
    let root = URL(filePath: "/tmp/LectureRecorderTests/Recordings", directoryHint: .isDirectory)

    final class Flag { var isRecording = false }

    func makeController(flag: Flag, output: AudioOutputKind?) -> PlaybackController {
        let defaults = UserDefaults(suiteName: "PlaybackDuringRecordingTests-\(UUID().uuidString)") ?? .standard
        return PlaybackController(
            player: player,
            storage: RecordingStorage(root: root, files: FakeFileStore()),
            defaults: defaults,
            isRecording: { flag.isRecording },
            outputInspector: output.map { FakeAudioOutput($0) }
        )
    }

    func makeRecording() -> Recording {
        Recording(title: "녹음", subject: nil, startedAt: date(2026, 3, 2, 10, 0), duration: 60, relativePath: "자료구조/2026-03-02_1000.m4a")
    }

    @Test func 녹음_중_스피커면_재생하지_않고_확인을_요청한다() {
        let flag = Flag()
        flag.isRecording = true
        let controller = makeController(flag: flag, output: .builtInSpeaker)
        controller.select(makeRecording())
        controller.togglePlayPause()
        #expect(!controller.isPlaying)
        #expect(controller.isConfirmingPlayback)
    }

    @Test func 그래도_재생을_누르면_튼다() {
        let flag = Flag()
        flag.isRecording = true
        let controller = makeController(flag: flag, output: .builtInSpeaker)
        controller.select(makeRecording())
        controller.play()
        controller.confirmPlaybackDuringRecording()
        #expect(controller.isPlaying)
        #expect(!controller.isConfirmingPlayback)
    }

    @Test func 취소하면_재생하지_않는다() {
        let flag = Flag()
        flag.isRecording = true
        let controller = makeController(flag: flag, output: .builtInSpeaker)
        controller.select(makeRecording())
        controller.play()
        controller.cancelPlaybackConfirmation()
        #expect(!controller.isPlaying)
        #expect(!controller.isConfirmingPlayback)
    }

    @Test func 녹음_중_이어폰이면_확인_없이_튼다() {
        let flag = Flag()
        flag.isRecording = true
        let controller = makeController(flag: flag, output: .external)
        controller.select(makeRecording())
        controller.play()
        #expect(controller.isPlaying)
        #expect(!controller.isConfirmingPlayback)
    }

    @Test func 녹음_중이_아니면_확인_없이_튼다() {
        let controller = makeController(flag: Flag(), output: .builtInSpeaker)
        controller.select(makeRecording())
        controller.play()
        #expect(controller.isPlaying)
    }

    @Test func 출력_장치를_알_수_없으면_확인한다() {
        let flag = Flag()
        flag.isRecording = true
        let controller = makeController(flag: flag, output: nil)
        controller.select(makeRecording())
        controller.play()
        #expect(controller.isConfirmingPlayback)
        #expect(!controller.isPlaying)
    }

    @Test func 한번_허락하면_같은_녹음_중에는_다시_묻지_않는다() {
        let flag = Flag()
        flag.isRecording = true
        let controller = makeController(flag: flag, output: .builtInSpeaker)
        controller.select(makeRecording())
        controller.play()
        controller.confirmPlaybackDuringRecording()
        controller.pause()
        controller.play()
        #expect(controller.isPlaying)
        #expect(!controller.isConfirmingPlayback)
    }

    @Test func 새_녹음이_시작되면_재생을_멈추고_허락을_잊는다() {
        let flag = Flag()
        flag.isRecording = true
        let controller = makeController(flag: flag, output: .builtInSpeaker)
        controller.select(makeRecording())
        controller.play()
        controller.confirmPlaybackDuringRecording()
        controller.recordingDidStart()
        #expect(!controller.isPlaying)
        controller.play()
        #expect(controller.isConfirmingPlayback)
    }

    @Test func 북마크로_이동해_재생해도_같은_판단을_거친다() {
        let flag = Flag()
        flag.isRecording = true
        let controller = makeController(flag: flag, output: .builtInSpeaker)
        let item = makeRecording()
        controller.select(item)
        let bookmark = Bookmark(time: 30, createdAt: date(2026, 3, 2, 10, 1))
        controller.play(from: bookmark)
        #expect(!controller.isPlaying)
        #expect(controller.isConfirmingPlayback)
    }
}
#endif
