import Foundation
import Testing
@testable import LectureCore

@Suite struct PausedAdviceTests {
    let pausedAt = date(2026, 3, 2, 10, 0)

    @Test func 십분_못_미치면_안내하지_않는다() {
        let now = pausedAt.addingTimeInterval(PausedAdvice.pausedReminderDelay - 1)  // 9분 59초
        #expect(PausedAdvice.notice(pausedAt: pausedAt, now: now) == nil)
    }

    @Test func 십분_정각부터_안내한다() {
        let now = pausedAt.addingTimeInterval(PausedAdvice.pausedReminderDelay)
        #expect(PausedAdvice.notice(pausedAt: pausedAt, now: now) == "일시정지 중입니다. 수업이 이어지면 다시 시작하세요")
    }

    @Test func 일시정지_중이_아니면_안내하지_않는다() {
        #expect(PausedAdvice.notice(pausedAt: nil, now: pausedAt.addingTimeInterval(3600)) == nil)
    }

    @Test func 기준_시간은_십분이다() {
        #expect(PausedAdvice.pausedReminderDelay == 600)
    }
}
