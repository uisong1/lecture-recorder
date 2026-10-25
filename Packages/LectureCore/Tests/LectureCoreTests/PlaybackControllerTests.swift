#if canImport(SwiftData)
import Foundation
import Testing
@testable import LectureCore

@MainActor
@Suite struct PlaybackControllerTests {
    let player = FakeAudioPlayer()
    let root = URL(filePath: "/tmp/LectureRecorderTests/Recordings", directoryHint: .isDirectory)

    func makeController() -> PlaybackController {
        PlaybackController(player: player, storage: RecordingStorage(root: root, files: FakeFileStore()))
    }

    func makeRecording(_ path: String = "자료구조/2026-03-02_1000.m4a") -> Recording {
        Recording(title: "녹음", subject: nil, startedAt: date(2026, 3, 2, 10, 0), duration: 60, relativePath: path)
    }

    @Test func 녹음을_고르면_파일을_불러온다() {
        let controller = makeController()
        let recording = makeRecording()
        controller.select(recording)
        #expect(controller.current === recording)
        #expect(player.loadedURLs.map(\.path) == ["/tmp/LectureRecorderTests/Recordings/자료구조/2026-03-02_1000.m4a"])
        #expect(!controller.isPlaying)
    }

    @Test func 재생과_일시정지를_번갈아_한다() {
        let controller = makeController()
        controller.select(makeRecording())
        controller.togglePlayPause()
        #expect(controller.isPlaying)
        controller.togglePlayPause()
        #expect(!controller.isPlaying)
    }

    @Test func 불러온_녹음이_없으면_재생하지_않는다() {
        let controller = makeController()
        controller.play()
        #expect(!controller.isPlaying)
    }

    @Test func 파일을_열_수_없으면_오류_문구를_보여준다() {
        player.loadError = CocoaError(.fileNoSuchFile)
        let controller = makeController()
        controller.select(makeRecording())
        #expect(controller.current == nil)
        #expect(controller.errorMessage == "녹음 파일을 열 수 없습니다. 파일이 옮겨졌거나 지워졌을 수 있습니다.")
    }

    @Test func 다른_녹음을_고르면_재생을_멈추고_새로_불러온다() {
        let controller = makeController()
        controller.select(makeRecording("a/1.m4a"))
        controller.play()
        controller.select(makeRecording("a/2.m4a"))
        #expect(!controller.isPlaying)
        #expect(player.loadedURLs.count == 2)
    }

    @Test func 같은_녹음을_다시_골라도_다시_불러오지_않는다() {
        let controller = makeController()
        let recording = makeRecording()
        controller.select(recording)
        controller.play()
        controller.select(recording)
        #expect(controller.isPlaying)
        #expect(player.loadedURLs.count == 1)
    }

    @Test func 재생이_끝나면_갱신_때_재생중_표시가_꺼진다() {
        let controller = makeController()
        controller.select(makeRecording())
        controller.play()
        player.isPlaying = false
        controller.refresh()
        #expect(!controller.isPlaying)
    }

    @Test func 슬라이더로_원하는_위치로_이동한다() {
        let controller = makeController()
        controller.select(makeRecording())
        controller.seek(to: 30)
        #expect(controller.currentTime == 30)
    }

    @Test func 이동_위치는_0에서_길이_사이로_맞춘다() {
        let controller = makeController()
        controller.select(makeRecording())
        controller.seek(to: -5)
        #expect(controller.currentTime == 0)
        controller.seek(to: 999)
        #expect(controller.currentTime == 60)
    }

    @Test func 불러온_녹음이_없으면_이동하지_않는다() {
        let controller = makeController()
        controller.seek(to: 10)
        #expect(player.currentTime == 0)
    }

    @Test func 배속은_네_단계를_고를_수_있다() {
        #expect(PlaybackRate.allCases.map(\.rawValue) == [1.0, 1.25, 1.5, 2.0])
        let controller = makeController()
        controller.select(makeRecording())
        for rate in PlaybackRate.allCases {
            controller.setRate(rate)
            #expect(controller.rate == rate)
            #expect(player.rate == rate.rawValue)
        }
    }

    @Test func 고른_배속은_다른_녹음을_골라도_유지된다() {
        let controller = makeController()
        controller.select(makeRecording("a/1.m4a"))
        controller.setRate(.x150)
        controller.select(makeRecording("a/2.m4a"))
        #expect(controller.rate == .x150)
        #expect(player.rate == 1.5)
    }
}
#endif
