#if canImport(SwiftData)
import Foundation
import SwiftData
import Testing
@testable import LectureCore

@Suite struct RecordingModelTests {
    @Test func 녹음을_저장하고_다시_불러온다() throws {
        let container = try LectureModelContainer.make(inMemory: true)
        let startedAt = Date(timeIntervalSince1970: 1_772_413_200)

        let writer = ModelContext(container)
        let subject = Subject(name: "자료구조", color: .green)
        writer.insert(subject)
        writer.insert(Recording(title: "3월 2일 자료구조", subject: subject, startedAt: startedAt, duration: 5_400, relativePath: "자료구조/2026-03-02_1000.m4a"))
        try writer.save()

        let reader = ModelContext(container)
        let recordings = try reader.fetch(FetchDescriptor<Recording>())
        let recording = try #require(recordings.first)
        #expect(recordings.count == 1)
        #expect(recording.title == "3월 2일 자료구조")
        #expect(recording.subject?.name == "자료구조")
        #expect(recording.startedAt == startedAt)
        #expect(recording.duration == 5_400)
        #expect(recording.relativePath == "자료구조/2026-03-02_1000.m4a")
    }

    @Test func 과목_없는_녹음은_미분류로_저장된다() throws {
        let container = try LectureModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        context.insert(Recording(title: "녹음", subject: nil, startedAt: .now, duration: 10, relativePath: "미분류/a.m4a"))
        try context.save()

        let fetched = try ModelContext(container).fetch(FetchDescriptor<Recording>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.subject == nil)
    }

    @Test func 과목을_지우면_녹음은_남고_미분류가_된다() throws {
        let container = try LectureModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let subject = Subject(name: "운영체제")
        context.insert(subject)
        context.insert(Recording(title: "녹음", subject: subject, startedAt: .now, duration: 10, relativePath: "운영체제/a.m4a"))
        try context.save()

        context.delete(subject)
        try context.save()

        let recordings = try context.fetch(FetchDescriptor<Recording>())
        #expect(recordings.count == 1)
        #expect(recordings.first?.subject == nil)
    }

    @Test func 과목을_지우면_시간표_칸도_지워진다() throws {
        let container = try LectureModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let subject = Subject(name: "운영체제")
        context.insert(subject)
        let slot = try TimeSlot(weekday: .monday, start: TimeOfDay(hour: 9), end: TimeOfDay(hour: 10), subject: subject)
        context.insert(slot)
        try context.save()

        context.delete(subject)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<TimeSlot>()) == 0)
    }

    @Test func 재생_시각은_저장하고_다시_불러와도_유지된다() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "test.store")
        let playedAt = Date(timeIntervalSince1970: 1_772_500_000)

        do {
            let container = try LectureModelContainer.make(url: url)
            let context = ModelContext(container)
            let played = Recording(title: "들은 것", subject: nil, startedAt: playedAt, duration: 60, relativePath: "a.m4a")
            played.lastPlayedAt = playedAt
            context.insert(played)
            context.insert(Recording(title: "안 들은 것", subject: nil, startedAt: playedAt, duration: 60, relativePath: "b.m4a"))
            try context.save()
        }

        let container = try LectureModelContainer.make(url: url)
        let recordings = try ModelContext(container).fetch(FetchDescriptor<Recording>())
        #expect(recordings.first { $0.title == "들은 것" }?.lastPlayedAt == playedAt)
        #expect(recordings.first { $0.title == "안 들은 것" }?.lastPlayedAt == nil)
        #expect(recordings.first { $0.title == "안 들은 것" }?.isUnplayed == true)
    }
}
#endif
