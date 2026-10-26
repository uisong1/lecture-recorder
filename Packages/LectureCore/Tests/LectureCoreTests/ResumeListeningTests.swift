#if canImport(SwiftData)
import Foundation
import Testing
@testable import LectureCore

@MainActor
@Suite struct ResumeListeningTests {
    func recording(
        _ path: String,
        position: TimeInterval = 600,
        playedAt: Date? = date(2026, 10, 26, 9, 0),
        duration: TimeInterval = 3_600,
        subject: Subject? = nil,
        startedAt: Date = date(2026, 10, 26, 10, 0)
    ) -> Recording {
        let recording = Recording(title: path, subject: subject, startedAt: startedAt, duration: duration, relativePath: path)
        recording.lastPlayedPosition = position
        recording.lastPlayedAt = playedAt
        return recording
    }

    func pick(_ list: [Recording], missing: Set<String> = []) -> Recording? {
        ResumeListening.pick(from: list, isPlayable: { !missing.contains($0.relativePath) })
    }

    @Test func 가장_최근에_재생한_녹음을_고른다() {
        let old = recording("old.m4a", playedAt: date(2026, 10, 24, 9, 0))
        let recent = recording("recent.m4a", playedAt: date(2026, 10, 26, 9, 0))
        let middle = recording("middle.m4a", playedAt: date(2026, 10, 25, 9, 0))
        #expect(pick([old, recent, middle]) === recent)
    }

    @Test func 끝까지_들은_녹음은_건너뛴다() {
        let finished = recording("finished.m4a", position: 0, playedAt: date(2026, 10, 26, 9, 0))
        let unfinished = recording("unfinished.m4a", playedAt: date(2026, 10, 25, 9, 0))
        #expect(pick([finished, unfinished]) === unfinished)
    }

    @Test func 끝_가까이까지_들은_녹음은_건너뛴다() {
        let margin = PlaybackController.finishedMargin
        let nearEnd = recording("end.m4a", position: 3_600 - margin)
        let justBefore = recording("before.m4a", position: 3_600 - margin - 1, playedAt: date(2026, 10, 25, 9, 0))
        #expect(pick([nearEnd]) == nil)
        #expect(pick([nearEnd, justBefore]) === justBefore)
    }

    @Test func 들던_위치가_없으면_고르지_않는다() {
        let neverPlayed = recording("new.m4a", position: 0, playedAt: nil)
        #expect(pick([neverPlayed]) == nil)
    }

    @Test func 파일이_없으면_다음_후보를_고른다() {
        let missing = recording("missing.m4a", playedAt: date(2026, 10, 26, 9, 0))
        let next = recording("next.m4a", playedAt: date(2026, 10, 25, 9, 0))
        #expect(pick([missing, next], missing: ["missing.m4a"]) === next)
        #expect(pick([missing], missing: ["missing.m4a"]) == nil)
    }

    @Test func 재생_시각을_모르는_예전_녹음은_가장_오래된_것으로_본다() {
        let legacy = recording("legacy.m4a", playedAt: nil)
        let dated = recording("dated.m4a", playedAt: date(2026, 1, 1, 9, 0))
        #expect(pick([legacy, dated]) === dated)
        #expect(pick([legacy]) === legacy)
    }

    @Test func 녹음이_하나도_없으면_고르지_않는다() {
        #expect(pick([]) == nil)
    }

    @Test func 남은_시간은_올림한_분으로_보인다() {
        #expect(ResumeListening.remainingText(seconds: 23 * 60) == "23분")
        #expect(ResumeListening.remainingText(seconds: 23 * 60 + 1) == "24분")
        #expect(ResumeListening.remainingText(seconds: 20) == "1분")
        #expect(ResumeListening.remainingText(seconds: 0) == "1분")
        #expect(ResumeListening.remainingText(seconds: 59 * 60) == "59분")
        #expect(ResumeListening.remainingText(seconds: 60 * 60) == "1시간")
        #expect(ResumeListening.remainingText(seconds: 65 * 60) == "1시간 5분")
    }

    @Test func 안내_글에_과목_날짜_남은_시간이_들어간다() {
        let subject = Subject(name: "자료구조")
        let item = recording("a.m4a", position: 3_600 - 23 * 60, subject: subject, startedAt: date(2026, 10, 26, 10, 0))
        #expect(ResumeListening.lineText(for: item, calendar: seoulCalendar) == "이어서 듣기: 자료구조 · 10월 26일 (남은 23분)")
    }

    @Test func 과목이_없으면_미분류로_보인다() {
        let item = recording("a.m4a", position: 3_000, startedAt: date(2026, 3, 2, 10, 0))
        #expect(ResumeListening.lineText(for: item, calendar: seoulCalendar) == "이어서 듣기: 미분류 · 3월 2일 (남은 10분)")
    }

    @Test func 고른_녹음을_불러와_마지막_위치부터_튼다() {
        let player = FakeAudioPlayer()
        let defaults = UserDefaults(suiteName: "ResumeListeningTests-\(UUID().uuidString)") ?? .standard
        let controller = PlaybackController(
            player: player,
            storage: RecordingStorage(root: URL(filePath: "/tmp/LectureRecorderTests/Recordings", directoryHint: .isDirectory), files: FakeFileStore()),
            defaults: defaults,
            outputInspector: FakeAudioOutput(.external)
        )
        let item = recording("a.m4a", position: 40, duration: 60)
        let picked = pick([item])
        controller.select(picked)
        controller.play()
        #expect(controller.current === item)
        #expect(controller.isPlaying)
        #expect(player.currentTime == 40)
    }

    @Test func 녹음_중_스피커면_이어_듣기도_확인을_거친다() {
        let player = FakeAudioPlayer()
        let defaults = UserDefaults(suiteName: "ResumeListeningTests-\(UUID().uuidString)") ?? .standard
        let controller = PlaybackController(
            player: player,
            storage: RecordingStorage(root: URL(filePath: "/tmp/LectureRecorderTests/Recordings", directoryHint: .isDirectory), files: FakeFileStore()),
            defaults: defaults,
            isRecording: { true },
            outputInspector: FakeAudioOutput(.builtInSpeaker)
        )
        controller.select(recording("a.m4a", position: 40, duration: 60))
        controller.play()
        #expect(!controller.isPlaying)
        #expect(controller.isConfirmingPlayback)
    }
}
#endif
