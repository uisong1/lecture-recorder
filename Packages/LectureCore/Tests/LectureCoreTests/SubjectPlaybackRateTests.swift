#if canImport(SwiftData)
import Foundation
import SwiftData
import Testing
@testable import LectureCore

@MainActor
@Suite struct SubjectPlaybackRateTests {
    let player = FakeAudioPlayer()
    let root = URL(filePath: "/tmp/LectureRecorderTests/Recordings", directoryHint: .isDirectory)
    let container: ModelContainer
    let defaults: UserDefaults
    let saves = SaveCounter()

    final class SaveCounter { var count = 0 }

    init() throws {
        container = try LectureModelContainer.make(inMemory: true)
        defaults = try #require(UserDefaults(suiteName: "SubjectPlaybackRateTests-\(UUID().uuidString)"))
    }

    func makeController() -> PlaybackController {
        let counter = saves
        return PlaybackController(
            player: player,
            storage: RecordingStorage(root: root, files: FakeFileStore()),
            savePosition: { counter.count += 1 },
            defaults: defaults
        )
    }

    func makeRecording(_ subject: Subject?, _ path: String) -> Recording {
        let recording = Recording(title: "녹음", subject: subject, startedAt: date(2026, 3, 2, 10, 0), duration: 60, relativePath: path)
        container.mainContext.insert(recording)
        return recording
    }

    func makeSubject(_ name: String) -> Subject {
        let subject = Subject(name: name)
        container.mainContext.insert(subject)
        return subject
    }

    @Test func 과목에서_고른_배속은_그_과목의_다른_녹음에서_다시_쓴다() {
        let subject = makeSubject("자료구조")
        let controller = makeController()
        controller.select(makeRecording(subject, "자료구조/1.m4a"))
        controller.setRate(.x200)
        controller.select(makeRecording(subject, "자료구조/2.m4a"))
        #expect(controller.rate == .x200)
        #expect(player.rate == 2.0)
        #expect(subject.playbackRate == .x200)
    }

    @Test func 과목마다_따로_기억한다() {
        let slow = makeSubject("수학")
        let fast = makeSubject("역사")
        let controller = makeController()
        let math = makeRecording(slow, "수학/1.m4a")
        let history = makeRecording(fast, "역사/1.m4a")
        controller.select(math)
        controller.setRate(.x075)
        controller.select(history)
        controller.setRate(.x250)
        controller.select(math)
        #expect(controller.rate == .x075)
        #expect(player.rate == 0.75)
        controller.select(history)
        #expect(controller.rate == .x250)
    }

    @Test func 기억이_없는_과목은_마지막으로_고른_속도를_쓴다() {
        let known = makeSubject("역사")
        let fresh = makeSubject("영어")
        let controller = makeController()
        controller.select(makeRecording(known, "역사/1.m4a"))
        controller.setRate(.x150)
        controller.select(makeRecording(fresh, "영어/1.m4a"))
        #expect(controller.rate == .x150)
        // 기억이 없던 과목에는 고르기 전까지 기록하지 않는다.
        #expect(fresh.playbackRate == nil)
    }

    @Test func 과목이_없는_녹음은_전체_속도를_쓰고_과목_속도를_덮지_않는다() {
        let subject = makeSubject("수학")
        let controller = makeController()
        controller.select(makeRecording(subject, "수학/1.m4a"))
        controller.setRate(.x075)
        controller.select(makeRecording(nil, "미분류/1.m4a"))
        #expect(controller.rate == .x075)
        controller.setRate(.x200)
        #expect(subject.playbackRate == .x075)
        controller.select(makeRecording(subject, "수학/2.m4a"))
        #expect(controller.rate == .x075)
    }

    @Test func 속도를_바꾸면_과목에_저장하고_같은_속도면_다시_저장하지_않는다() {
        let subject = makeSubject("수학")
        let controller = makeController()
        controller.select(makeRecording(subject, "수학/1.m4a"))
        let before = saves.count
        controller.setRate(.x125)
        #expect(saves.count == before + 1)
        controller.setRate(.x125)
        #expect(saves.count == before + 1)
    }

    @Test func 알_수_없는_저장값은_기억이_없는_것으로_본다() {
        let subject = makeSubject("수학")
        subject.playbackRateRawValue = 1.7
        #expect(subject.playbackRate == nil)
        let controller = makeController()
        controller.select(makeRecording(subject, "수학/1.m4a"))
        #expect(controller.rate == .normal)
    }

    @Test func 새_과목은_기억한_속도가_없다() {
        #expect(Subject(name: "새 과목").playbackRate == nil)
    }
}
#endif
