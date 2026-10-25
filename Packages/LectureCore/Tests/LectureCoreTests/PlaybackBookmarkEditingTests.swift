#if canImport(SwiftData)
import Foundation
import SwiftData
import Testing
@testable import LectureCore

@MainActor
@Suite struct PlaybackBookmarkEditingTests {
    let container: ModelContainer
    let player = FakeAudioPlayer()
    let root = URL(filePath: "/tmp/LectureRecorderTests/Recordings", directoryHint: .isDirectory)
    var context: ModelContext { container.mainContext }

    init() throws {
        container = try LectureModelContainer.make(inMemory: true)
    }

    func makeController() -> PlaybackController {
        PlaybackController(
            player: player,
            storage: RecordingStorage(root: root, files: FakeFileStore()),
            bookmarkManager: BookmarkManager(context: context),
            now: { date(2026, 3, 2, 11, 0) }
        )
    }

    func makeRecording() -> Recording {
        let recording = Recording(title: "녹음", subject: nil, startedAt: date(2026, 3, 2, 10, 0), duration: 60, relativePath: "미분류/a.m4a")
        context.insert(recording)
        return recording
    }

    @Test func 지금_재생_위치에_북마크를_추가한다() {
        let controller = makeController()
        let recording = makeRecording()
        controller.select(recording)
        player.currentTime = 42
        let bookmark = controller.addBookmarkAtCurrentTime()
        #expect(bookmark?.time == 42)
        #expect(bookmark?.createdAt == date(2026, 3, 2, 11, 0))
        #expect(controller.bookmarks.map(\.time) == [42])
    }

    @Test func 같은_자리에는_북마크를_또_만들지_않는다() {
        let controller = makeController()
        controller.select(makeRecording())
        player.currentTime = 10
        controller.addBookmarkAtCurrentTime()
        player.currentTime = 10.5
        let duplicate = controller.addBookmarkAtCurrentTime()
        #expect(duplicate == nil)
        #expect(controller.bookmarks.count == 1)
        #expect(controller.errorMessage == "이 위치에는 이미 북마크가 있습니다.")
    }

    @Test func 간격이_충분하면_가까운_자리에도_추가한다() {
        let controller = makeController()
        controller.select(makeRecording())
        player.currentTime = 10
        controller.addBookmarkAtCurrentTime()
        player.currentTime = 11
        #expect(controller.addBookmarkAtCurrentTime() != nil)
        #expect(controller.bookmarks.count == 2)
    }

    @Test func 불러온_녹음이_없으면_추가하지_않는다() {
        let controller = makeController()
        #expect(controller.addBookmarkAtCurrentTime() == nil)
    }

    @Test func 메모를_고친다() {
        let controller = makeController()
        controller.select(makeRecording())
        player.currentTime = 20
        let bookmark = controller.addBookmarkAtCurrentTime()
        controller.updateNote(of: bookmark!, to: "  시험 범위  ")
        #expect(controller.bookmarks.first?.note == "시험 범위")
    }

    @Test func 북마크를_삭제하면_목록과_저장소에서_사라진다() throws {
        let controller = makeController()
        controller.select(makeRecording())
        player.currentTime = 20
        let first = controller.addBookmarkAtCurrentTime()
        player.currentTime = 40
        controller.addBookmarkAtCurrentTime()
        controller.delete(first!)
        #expect(controller.bookmarks.map(\.time) == [40])
        #expect(try context.fetch(FetchDescriptor<Bookmark>()).count == 1)
    }
}
#endif
