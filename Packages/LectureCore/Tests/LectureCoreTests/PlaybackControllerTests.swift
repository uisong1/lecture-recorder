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

    func addBookmarks(_ times: [TimeInterval], to recording: Recording) {
        for time in times {
            recording.bookmarks.append(Bookmark(time: time, createdAt: date(2026, 3, 2, 10, 30)))
        }
    }

    @Test func 북마크를_누르면_그_시점부터_재생한다() {
        let controller = makeController()
        let recording = makeRecording()
        addBookmarks([45], to: recording)
        controller.select(recording)
        controller.play(from: controller.bookmarks[0])
        #expect(controller.currentTime == 40)
        #expect(controller.isPlaying)
        #expect(controller.bookmarks[0].time == 45)
    }

    @Test func 일시정지_중에도_북마크로_이동하면_재생이_시작된다() {
        let controller = makeController()
        let recording = makeRecording()
        addBookmarks([10], to: recording)
        controller.select(recording)
        controller.play()
        controller.pause()
        controller.play(from: controller.bookmarks[0])
        #expect(controller.isPlaying)
        #expect(controller.currentTime == 5)
    }

    @Test func 북마크가_5초_안쪽이면_처음부터_튼다() {
        let controller = makeController()
        let recording = makeRecording()
        addBookmarks([3], to: recording)
        controller.select(recording)
        controller.play(from: controller.bookmarks[0])
        #expect(controller.currentTime == 0)
        #expect(controller.bookmarks[0].time == 3)
    }

    @Test func 북마크가_정확히_5초면_0초에서_튼다() {
        #expect(PlaybackController.playbackStart(forBookmarkAt: 5, duration: 60) == 0)
        #expect(PlaybackController.playbackStart(forBookmarkAt: 5.5, duration: 60) == 0.5)
        #expect(PlaybackController.playbackStart(forBookmarkAt: 0, duration: 60) == 0)
    }

    @Test func 길이를_넘는_시점은_앞당긴_뒤에도_끝을_넘지_않는다() {
        #expect(PlaybackController.playbackStart(forBookmarkAt: 62, duration: 60) == 57)
        #expect(PlaybackController.playbackStart(forBookmarkAt: 999, duration: 60) == 60)
        #expect(PlaybackController.playbackStart(forBookmarkAt: 30, duration: 0) == 0)
    }

    @Test func 길이를_넘는_북마크는_끝으로_맞춘다() {
        let controller = makeController()
        let recording = makeRecording()
        addBookmarks([999], to: recording)
        controller.select(recording)
        controller.play(from: controller.bookmarks[0])
        #expect(controller.currentTime == 60)
    }

    @Test func 슬라이더_표시_위치는_길이_대비_비율이다() {
        let controller = makeController()
        let recording = makeRecording()
        addBookmarks([30, 15, 999], to: recording)
        controller.select(recording)
        #expect(controller.bookmarks.map(\.time) == [15, 30, 999])
        #expect(controller.bookmarkMarkers == [0.25, 0.5, 1])
    }

    @Test func 불러온_녹음이_없으면_북마크_표시가_없다() {
        let controller = makeController()
        #expect(controller.bookmarks.isEmpty)
        #expect(controller.bookmarkMarkers.isEmpty)
    }

    @Test func 녹음_시작_알림으로_재생을_멈출_수_있다() async throws {
        let controller = makeController()
        controller.select(makeRecording())
        controller.play()
        #expect(controller.isPlaying)
        controller.pause()
        #expect(!controller.isPlaying)
        #expect(!player.isPlaying)
    }

    // MARK: 마지막 재생 위치

    @Test func 일시정지하면_그_위치를_녹음에_적어_둔다() {
        let controller = makeController()
        let recording = makeRecording()
        controller.select(recording)
        controller.play()
        player.currentTime = 25
        controller.pause()
        #expect(recording.lastPlayedPosition == 25)
    }

    @Test func 다시_고르면_적어_둔_위치에서_이어_듣는다() {
        let controller = makeController()
        let recording = makeRecording()
        recording.lastPlayedPosition = 40
        controller.select(recording)
        #expect(controller.currentTime == 40)
    }

    @Test func 다른_녹음으로_옮기면_듣던_위치를_적어_둔다() {
        let controller = makeController()
        let first = makeRecording("a/1.m4a")
        controller.select(first)
        controller.seek(to: 12)
        controller.select(makeRecording("a/2.m4a"))
        #expect(first.lastPlayedPosition == 12)
    }

    @Test func 끝에서_3초_안이면_다음에는_처음부터_듣는다() {
        let controller = makeController()
        let recording = makeRecording()
        recording.lastPlayedPosition = 30
        controller.select(recording)
        controller.play()
        player.currentTime = 57
        controller.pause()
        #expect(recording.lastPlayedPosition == 0)
        controller.select(nil)
        controller.select(recording)
        #expect(controller.currentTime == 0)
    }

    @Test func 끝에서_3초_밖이면_위치를_기억한다() {
        let controller = makeController()
        let recording = makeRecording()
        controller.select(recording)
        controller.play()
        player.currentTime = 56.9
        controller.pause()
        #expect(recording.lastPlayedPosition == 56.9)
    }

    @Test func 저장된_위치가_끝_근처면_처음부터_시작한다() {
        let controller = makeController()
        let recording = makeRecording()
        recording.lastPlayedPosition = 59
        controller.select(recording)
        #expect(controller.currentTime == 0)
    }

    @Test func 끝까지_들어서_재생이_멈추면_위치를_지운다() {
        let controller = makeController()
        let recording = makeRecording()
        recording.lastPlayedPosition = 20
        controller.select(recording)
        controller.play()
        player.currentTime = 60
        player.isPlaying = false
        controller.refresh()
        #expect(recording.lastPlayedPosition == 0)
    }

    @Test func 위치가_바뀔_때만_저장을_요청한다() {
        var saved = 0
        let controller = PlaybackController(
            player: player,
            storage: RecordingStorage(root: root, files: FakeFileStore()),
            savePosition: { saved += 1 }
        )
        let recording = makeRecording()
        recording.lastPlayedAt = date(2026, 3, 1, 9, 0)
        controller.select(recording)
        controller.play()
        controller.pause()
        #expect(saved == 0)
        controller.play()
        player.currentTime = 10
        controller.pause()
        controller.pause()
        #expect(saved == 1)
    }

    // MARK: 재생 기록 (안 들음 표시)

    @Test func 재생을_시작하면_재생_시각을_적고_바로_저장을_요청한다() {
        var saved = 0
        let startedAt = date(2026, 4, 1, 20, 0)
        let controller = PlaybackController(
            player: player,
            storage: RecordingStorage(root: root, files: FakeFileStore()),
            now: { startedAt },
            savePosition: { saved += 1 }
        )
        let recording = makeRecording()
        controller.select(recording)
        #expect(recording.lastPlayedAt == nil)
        #expect(recording.isUnplayed)
        controller.play()
        #expect(recording.lastPlayedAt == startedAt)
        #expect(!recording.isUnplayed)
        #expect(saved == 1)
    }

    @Test func 녹음을_불러오기만_하면_들은_것으로_치지_않는다() {
        let controller = makeController()
        let recording = makeRecording()
        controller.select(recording)
        #expect(recording.lastPlayedAt == nil)
    }

    @Test func 파일을_못_열어_재생하지_못하면_재생_시각을_적지_않는다() {
        let controller = makeController()
        let recording = makeRecording()
        player.loadError = CocoaError(.fileNoSuchFile)
        controller.select(recording)
        controller.play()
        #expect(recording.lastPlayedAt == nil)
    }

    @Test func 끝까지_들어_위치가_0이어도_들은_녹음으로_남는다() {
        let controller = makeController()
        let recording = makeRecording()
        controller.select(recording)
        controller.play()
        player.currentTime = 60
        player.isPlaying = false
        controller.refresh()
        #expect(recording.lastPlayedPosition == 0)
        #expect(!recording.isUnplayed)
    }

    // MARK: 건너뛰기

    @Test func 앞으로_건너뛰면_15초_뒤로_간다() {
        let controller = makeController()
        controller.select(makeRecording())
        controller.seek(to: 10)
        controller.skipForward()
        #expect(controller.currentTime == 25)
    }

    @Test func 뒤로_건너뛰면_15초_앞으로_간다() {
        let controller = makeController()
        controller.select(makeRecording())
        controller.seek(to: 40)
        controller.skipBackward()
        #expect(controller.currentTime == 25)
    }

    @Test func 건너뛰기는_처음과_끝을_넘지_않는다() {
        let controller = makeController()
        controller.select(makeRecording())
        controller.seek(to: 5)
        controller.skipBackward()
        #expect(controller.currentTime == 0)
        controller.seek(to: 50)
        controller.skipForward()
        #expect(controller.currentTime == 60)
    }

    @Test func 정확히_15초_남았을_때_앞으로_건너뛰면_끝에_닿는다() {
        let controller = makeController()
        controller.select(makeRecording())
        controller.seek(to: 45)
        controller.skipForward()
        #expect(controller.currentTime == 60)
    }

    @Test func 불러온_녹음이_없으면_건너뛰지_않는다() {
        let controller = makeController()
        controller.skipForward()
        #expect(player.currentTime == 0)
    }

    @Test func 건너뛰어도_재생_상태는_그대로다() {
        let controller = makeController()
        controller.select(makeRecording())
        controller.play()
        controller.skipForward()
        #expect(controller.isPlaying)
        controller.pause()
        controller.skipBackward()
        #expect(!controller.isPlaying)
    }
}
#endif
