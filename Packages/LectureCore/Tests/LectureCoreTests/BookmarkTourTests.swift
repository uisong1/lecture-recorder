#if canImport(SwiftData)
import Foundation
import SwiftData
import Testing
@testable import LectureCore

@MainActor
@Suite struct BookmarkTourTests {
    let container: ModelContainer
    let player = FakeAudioPlayer()
    let root = URL(filePath: "/tmp/LectureRecorderTests/Recordings", directoryHint: .isDirectory)
    var context: ModelContext { container.mainContext }

    init() throws {
        container = try LectureModelContainer.make(inMemory: true)
        player.durationForNextLoad = 600
    }

    func makeController(missing: Set<String> = []) -> PlaybackController {
        PlaybackController(
            player: player,
            storage: RecordingStorage(root: root, files: FakeFileStore()),
            defaults: UserDefaults(suiteName: "BookmarkTourTests-\(UUID().uuidString)") ?? .standard,
            isPlayable: { !missing.contains($0.relativePath) }
        )
    }

    func makeRecording(_ path: String, day: Int = 2, duration: TimeInterval = 600, bookmarks: [TimeInterval]) -> (Recording, [BookmarkEntry]) {
        let recording = Recording(title: path, subject: nil, startedAt: date(2026, 3, day, 10, 0), duration: duration, relativePath: path)
        context.insert(recording)
        let entries = bookmarks.map { time -> BookmarkEntry in
            let bookmark = Bookmark(time: time, createdAt: date(2026, 3, day, 11, 0), recording: recording)
            context.insert(bookmark)
            return BookmarkEntry(bookmark: bookmark, recording: recording)
        }
        return (recording, entries)
    }

    // MARK: 구간 계산

    @Test func 북마크는_5초_앞에서_30초_구간이_된다() {
        let spans = BookmarkTour.spans(bookmarkTimes: [100], duration: 600)
        #expect(spans.map(\.start) == [95])
        #expect(spans.map(\.end) == [125])
    }

    @Test func 겹치거나_맞닿는_구간은_하나로_잇는다() {
        // 95~125, 120~150 겹침, 150~180은 맞닿아 → 95~180 하나. 195~225는 따로.
        let spans = BookmarkTour.spans(bookmarkTimes: [200, 125, 155, 100], duration: 600)
        #expect(spans.map(\.start) == [95, 195])
        #expect(spans.map(\.end) == [180, 225])
    }

    @Test func 일_초라도_떨어지면_나눈다() {
        let spans = BookmarkTour.spans(bookmarkTimes: [10, 41], duration: 600)
        #expect(spans.count == 2)
    }

    @Test func 녹음_끝을_넘는_구간은_자르고_끝_밖_북마크는_건너뛴다() {
        let spans = BookmarkTour.spans(bookmarkTimes: [590, 700], duration: 600)
        #expect(spans.map(\.start) == [585])
        #expect(spans.map(\.end) == [600])
    }

    @Test func 처음_5초_안의_북마크는_0초부터_시작한다() {
        let spans = BookmarkTour.spans(bookmarkTimes: [3], duration: 600)
        #expect(spans.map(\.start) == [0])
        #expect(spans.map(\.end) == [30])
    }

    @Test func 길이를_모르면_자르지_않는다() {
        let spans = BookmarkTour.spans(bookmarkTimes: [100], duration: 0)
        #expect(spans.map(\.end) == [125])
    }

    @Test func 북마크가_없으면_구간도_없다() {
        #expect(BookmarkTour.spans(bookmarkTimes: [], duration: 600).isEmpty)
        #expect(BookmarkTour.stops(for: [], isPlayable: { _ in true }).isEmpty)
    }

    @Test func 녹음은_날짜순으로_이어지고_파일_없는_녹음은_건너뛴다() {
        let (later, laterEntries) = makeRecording("later.m4a", day: 9, bookmarks: [50])
        let (earlier, earlierEntries) = makeRecording("earlier.m4a", day: 2, bookmarks: [80, 10])
        let (_, missingEntries) = makeRecording("missing.m4a", day: 5, bookmarks: [20])
        let stops = BookmarkTour.stops(
            for: laterEntries + missingEntries + earlierEntries,
            isPlayable: { $0.relativePath != "missing.m4a" }
        )
        #expect(stops.map(\.recording) == [earlier, earlier, later])
        #expect(stops.map(\.start) == [5, 75, 45])
    }

    // MARK: 재생

    @Test func 첫_구간부터_틀고_구간_끝에서_다음으로_넘어간다() {
        let controller = makeController()
        let (recording, entries) = makeRecording("a.m4a", bookmarks: [100, 300])
        controller.startBookmarkTour(entries: entries)
        #expect(controller.isTouring)
        #expect(controller.current === recording)
        #expect(player.currentTime == 95)
        #expect(controller.isPlaying)
        #expect(controller.tourPositionText == "1/2 북마크 구간")

        player.currentTime = 124.9
        controller.refresh()
        #expect(controller.tourIndex == 0)

        player.currentTime = 125
        controller.refresh()
        #expect(controller.tourIndex == 1)
        #expect(player.currentTime == 295)
        #expect(controller.tourPositionText == "2/2 북마크 구간")
    }

    @Test func 마지막_구간이_끝나면_멈추고_이어_듣기가_꺼진다() {
        let controller = makeController()
        let (_, entries) = makeRecording("a.m4a", bookmarks: [100])
        controller.startBookmarkTour(entries: entries)
        player.currentTime = 125
        controller.refresh()
        #expect(!controller.isTouring)
        #expect(!controller.isPlaying)
        #expect(controller.tourPositionText == nil)
    }

    @Test func 녹음_끝에서_스스로_멈추면_다음_구간으로_넘어간다() {
        let controller = makeController()
        let (_, first) = makeRecording("a.m4a", day: 2, bookmarks: [595])
        let (second, secondEntries) = makeRecording("b.m4a", day: 3, bookmarks: [100])
        controller.startBookmarkTour(entries: first + secondEntries)
        player.currentTime = 600
        player.isPlaying = false
        controller.refresh()
        #expect(controller.tourIndex == 1)
        #expect(controller.current === second)
        #expect(controller.isPlaying)
    }

    @Test func 건너뛰기로_앞뒤_구간으로_옮긴다() {
        let controller = makeController()
        let (_, entries) = makeRecording("a.m4a", bookmarks: [100, 300, 500])
        controller.startBookmarkTour(entries: entries)
        controller.nextTourStop()
        controller.nextTourStop()
        #expect(controller.tourIndex == 2)
        controller.previousTourStop()
        #expect(controller.tourIndex == 1)
        #expect(player.currentTime == 295)
        controller.previousTourStop()
        controller.previousTourStop()
        #expect(controller.tourIndex == 0)
        #expect(player.currentTime == 95)
    }

    @Test func 멈춤_버튼으로_끝내면_재생도_멈춘다() {
        let controller = makeController()
        let (_, entries) = makeRecording("a.m4a", bookmarks: [100, 300])
        controller.startBookmarkTour(entries: entries)
        controller.stopBookmarkTour()
        #expect(!controller.isTouring)
        #expect(!controller.isPlaying)
    }

    @Test func 일시정지해도_이어_듣기는_유지된다() {
        let controller = makeController()
        let (_, entries) = makeRecording("a.m4a", bookmarks: [100, 300])
        controller.startBookmarkTour(entries: entries)
        controller.pause()
        controller.refresh()
        #expect(controller.isTouring)
        #expect(controller.tourIndex == 0)
    }

    @Test func 다른_녹음을_고르거나_북마크를_누르면_일반_재생으로_돌아온다() {
        let controller = makeController()
        let (_, entries) = makeRecording("a.m4a", bookmarks: [100])
        let (other, _) = makeRecording("b.m4a", bookmarks: [])
        controller.startBookmarkTour(entries: entries)
        controller.select(other)
        #expect(!controller.isTouring)

        let (recording, more) = makeRecording("c.m4a", bookmarks: [200, 400])
        controller.startBookmarkTour(entries: more)
        controller.play(from: more[1].bookmark)
        #expect(!controller.isTouring)
        #expect(controller.current === recording)
    }

    @Test func 파일이_없는_녹음은_건너뛰고_모두_없으면_안내한다() {
        let controller = makeController(missing: ["gone.m4a"])
        let (_, goneEntries) = makeRecording("gone.m4a", day: 2, bookmarks: [100])
        let (ok, okEntries) = makeRecording("ok.m4a", day: 3, bookmarks: [100])
        controller.startBookmarkTour(entries: goneEntries + okEntries)
        #expect(controller.tourStops.count == 1)
        #expect(controller.current === ok)

        let none = makeController(missing: ["gone.m4a"])
        none.startBookmarkTour(entries: goneEntries)
        #expect(!none.isTouring)
        #expect(none.errorMessage == "이어 들을 북마크가 없습니다.")
    }

    @Test func 불러오기에_실패하는_녹음은_건너뛴다() {
        let controller = makeController()
        let (_, entries) = makeRecording("a.m4a", bookmarks: [100])
        player.loadError = CocoaError(.fileReadCorruptFile)
        controller.startBookmarkTour(entries: entries)
        #expect(!controller.isTouring)
        #expect(!controller.isPlaying)
    }

    @Test func 빈_목록이면_아무것도_틀지_않는다() {
        let controller = makeController()
        controller.startBookmarkTour(entries: [])
        #expect(!controller.isTouring)
        #expect(controller.current == nil)
        #expect(controller.errorMessage == "이어 들을 북마크가 없습니다.")
    }
}
#endif
