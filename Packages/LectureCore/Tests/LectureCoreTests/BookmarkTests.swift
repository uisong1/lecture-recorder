#if canImport(SwiftData)
import Foundation
import SwiftData
import Testing
@testable import LectureCore

@MainActor
@Suite struct BookmarkTests {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }
    let now = date(2026, 3, 2, 10, 30)

    init() throws {
        container = try LectureModelContainer.make(inMemory: true)
    }

    func makeRecording() -> Recording {
        let recording = Recording(title: "녹음", subject: nil, startedAt: date(2026, 3, 2, 10, 0), duration: 3000, relativePath: "미분류/a.m4a")
        context.insert(recording)
        return recording
    }

    @Test func 한_녹음에_북마크를_여러_개_저장한다() throws {
        let recording = makeRecording()
        let manager = BookmarkManager(context: context)
        try manager.add(to: recording, at: 120, note: "시험 범위", now: now)
        try manager.add(to: recording, at: 30, now: now)
        #expect(recording.bookmarks.count == 2)
        #expect(recording.sortedBookmarks.map(\.time) == [30, 120])
        #expect(recording.sortedBookmarks.last?.note == "시험 범위")
    }

    @Test func 저장한_북마크를_다시_불러온다() throws {
        let recording = makeRecording()
        try BookmarkManager(context: context).add(to: recording, at: 45, note: "정의", now: now)
        let fetched = try context.fetch(FetchDescriptor<Bookmark>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.time == 45)
        #expect(fetched.first?.createdAt == now)
        #expect(fetched.first?.recording === recording)
    }

    @Test func 북마크를_삭제하면_다른_북마크는_남는다() throws {
        let recording = makeRecording()
        let manager = BookmarkManager(context: context)
        let first = try manager.add(to: recording, at: 10, now: now)
        try manager.add(to: recording, at: 20, now: now)
        try manager.delete(first)
        #expect(recording.sortedBookmarks.map(\.time) == [20])
        #expect(try context.fetch(FetchDescriptor<Bookmark>()).count == 1)
    }

    @Test func 메모를_고칠_수_있다() throws {
        let recording = makeRecording()
        let manager = BookmarkManager(context: context)
        let bookmark = try manager.add(to: recording, at: 10, now: now)
        try manager.updateNote(bookmark, to: "과제 공지")
        #expect(bookmark.note == "과제 공지")
    }

    @Test func 시점이_음수면_0으로_맞춘다() throws {
        let bookmark = try BookmarkManager(context: context).add(to: makeRecording(), at: -3, now: now)
        #expect(bookmark.time == 0)
    }

    @Test func 녹음을_지우면_북마크도_함께_지워진다() throws {
        let recording = makeRecording()
        try BookmarkManager(context: context).add(to: recording, at: 10, now: now)
        context.delete(recording)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<Bookmark>()).isEmpty)
    }
}
#endif
