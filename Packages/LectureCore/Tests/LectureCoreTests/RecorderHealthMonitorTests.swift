import Testing
@testable import LectureCore

@MainActor
@Suite struct RecorderHealthMonitorTests {
    let recorder = FakeAudioRecorder()

    @Test func 시간이_늘면_건강하다() {
        var monitor = RecorderHealthMonitor()
        for step in 1...5 {
            recorder.currentTime = Double(step) * 10
            #expect(monitor.check(recorder, isPaused: false) == nil)
        }
    }

    @Test func 연속_세_번_안_늘면_멈춤으로_본다() {
        var monitor = RecorderHealthMonitor()
        recorder.currentTime = 100
        #expect(monitor.check(recorder, isPaused: false) == nil)  // 기준
        #expect(monitor.check(recorder, isPaused: false) == nil)  // 10초
        #expect(monitor.check(recorder, isPaused: false) == nil)  // 20초
        #expect(monitor.check(recorder, isPaused: false) == .noProgress)  // 30초
    }

    @Test func 녹음기가_끝났다고_하면_바로_멈춤으로_본다() {
        var monitor = RecorderHealthMonitor()
        recorder.currentTime = 10
        #expect(monitor.check(recorder, isPaused: false) == nil)

        recorder.hasEnded = true

        #expect(monitor.check(recorder, isPaused: false) == .recorderEnded)
    }

    @Test func 일시정지_중에는_시간이_안_늘어도_멈춤으로_보지_않는다() {
        var monitor = RecorderHealthMonitor()
        recorder.currentTime = 100
        for _ in 1...10 { #expect(monitor.check(recorder, isPaused: true) == nil) }
        // 재개한 뒤 곧바로 멈춘 것으로 보지 않는다.
        #expect(monitor.check(recorder, isPaused: false) == nil)
    }

    @Test func reset_하면_새_녹음처럼_기준부터_다시_잡는다() {
        var monitor = RecorderHealthMonitor()
        recorder.currentTime = 100
        _ = monitor.check(recorder, isPaused: false)
        _ = monitor.check(recorder, isPaused: false)
        _ = monitor.check(recorder, isPaused: false)

        monitor.reset()

        #expect(monitor.check(recorder, isPaused: false) == nil)
        #expect(monitor.check(recorder, isPaused: false) == nil)
    }

    @Test func 안내_문구() {
        #expect(RecorderHealthMonitor.unsavedNotice == "녹음이 멈춘 것 같습니다. 녹음을 다시 시작하세요.")
        #expect(RecorderHealthMonitor.savedNotice(title: "자료구조 3주차") == "녹음이 멈춘 것 같습니다. '자료구조 3주차' 녹음을 여기까지 저장했습니다. 녹음을 다시 시작하세요.")
    }
}
