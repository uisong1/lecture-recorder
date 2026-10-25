import Testing
@testable import LectureCore

@Suite struct RecorderStallDetectorTests {
    @Test func 시간이_계속_늘면_정상이다() {
        var detector = RecorderStallDetector()
        for step in 1...10 {
            #expect(detector.update(elapsed: Double(step) * 10, isPaused: false, recorderEnded: false) == .healthy)
        }
    }

    @Test func 첫_점검은_기준만_잡는다() {
        var detector = RecorderStallDetector()
        #expect(detector.update(elapsed: 0, isPaused: false, recorderEnded: false) == .healthy)
        #expect(detector.stagnantChecks == 0)
    }

    @Test func 연속_두_번_안_늘면_아직_정상이고_세_번째에_멈춤으로_본다() {
        var detector = RecorderStallDetector()
        _ = detector.update(elapsed: 100, isPaused: false, recorderEnded: false)
        #expect(detector.update(elapsed: 100, isPaused: false, recorderEnded: false) == .healthy)  // 10초
        #expect(detector.update(elapsed: 100, isPaused: false, recorderEnded: false) == .healthy)  // 20초
        #expect(detector.update(elapsed: 100, isPaused: false, recorderEnded: false) == .stalled(.noProgress))  // 30초
    }

    @Test func 멈춘_뒤_다시_늘면_세던_횟수를_지운다() {
        var detector = RecorderStallDetector()
        _ = detector.update(elapsed: 100, isPaused: false, recorderEnded: false)
        _ = detector.update(elapsed: 100, isPaused: false, recorderEnded: false)
        _ = detector.update(elapsed: 100, isPaused: false, recorderEnded: false)
        #expect(detector.update(elapsed: 110, isPaused: false, recorderEnded: false) == .healthy)
        #expect(detector.stagnantChecks == 0)
        #expect(detector.update(elapsed: 110, isPaused: false, recorderEnded: false) == .healthy)
        #expect(detector.update(elapsed: 110, isPaused: false, recorderEnded: false) == .healthy)
    }

    @Test func 일시정지_중에는_시간이_안_늘어도_경고하지_않는다() {
        var detector = RecorderStallDetector()
        _ = detector.update(elapsed: 100, isPaused: false, recorderEnded: false)
        for _ in 1...10 {
            #expect(detector.update(elapsed: 100, isPaused: true, recorderEnded: false) == .healthy)
        }
        // 재개한 직후 첫 점검부터 다시 센다.
        #expect(detector.update(elapsed: 100, isPaused: false, recorderEnded: false) == .healthy)
        #expect(detector.stagnantChecks == 1)
    }

    @Test func 녹음기가_끝났다고_알리면_바로_멈춤으로_본다() {
        var detector = RecorderStallDetector()
        _ = detector.update(elapsed: 100, isPaused: false, recorderEnded: false)
        #expect(detector.update(elapsed: 110, isPaused: false, recorderEnded: true) == .stalled(.recorderEnded))
    }

    @Test func 일시정지_중에는_녹음기가_끝났다는_값도_무시한다() {
        var detector = RecorderStallDetector()
        #expect(detector.update(elapsed: 0, isPaused: true, recorderEnded: true) == .healthy)
    }
}
