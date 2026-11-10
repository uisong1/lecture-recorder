import Foundation
import Testing
@testable import LectureCore

@Suite struct NotchAlertTests {
    /// 월 10:00~11:15 자료구조, 월 13:00~14:00 + 14:00~15:00 알고리즘(연강).
    let schedule: ClassSchedule<String>

    init() throws {
        schedule = ClassSchedule<String>(entries: [
            .init(period: try period(.monday, (10, 0), (11, 15)), subjectID: "자료구조"),
            .init(period: try period(.monday, (13, 0), (14, 0)), subjectID: "알고리즘"),
            .init(period: try period(.monday, (14, 0), (15, 0)), subjectID: "알고리즘"),
        ])
    }

    private func alert(
        at now: Date,
        recorded: [(subjectID: String, startedAt: Date)] = [],
        isRecording: Bool = false,
        dismissed: Set<Date> = []
    ) -> NotchAlert<String>? {
        schedule.activeNotchAlert(now: now, calendar: seoulCalendar, recorded: recorded, isRecording: isRecording, dismissedStarts: dismissed)
    }

    @Test func 시작_5분_뒤_정각부터_켜지고_4분_59초는_아직_꺼져_있다() {
        #expect(alert(at: date(2026, 3, 2, 10, 4, second: 59)) == nil)
        let on = alert(at: date(2026, 3, 2, 10, 5))
        #expect(on?.subjectID == "자료구조")
        #expect(on?.classStart == date(2026, 3, 2, 10, 0))
    }

    @Test func 켜진_지_10분_뒤_정각에_꺼진다() {
        #expect(alert(at: date(2026, 3, 2, 10, 14, second: 59)) != nil)
        #expect(alert(at: date(2026, 3, 2, 10, 15)) == nil)
        #expect(alert(at: date(2026, 3, 2, 10, 5))?.expiresAt == date(2026, 3, 2, 10, 15))
    }

    @Test func 수업이_먼저_끝나면_그_시각에_꺼진다() throws {
        let short = ClassSchedule<String>(entries: [.init(period: try period(.monday, (10, 0), (10, 8)), subjectID: "짧은수업")])
        let now = date(2026, 3, 2, 10, 6)
        #expect(short.activeNotchAlert(now: now, calendar: seoulCalendar, isRecording: false)?.expiresAt == date(2026, 3, 2, 10, 8))
        #expect(short.activeNotchAlert(now: date(2026, 3, 2, 10, 8), calendar: seoulCalendar, isRecording: false) == nil)
    }

    @Test func 수업_없는_시간과_다른_요일에는_꺼져_있다() {
        #expect(alert(at: date(2026, 3, 2, 12, 0)) == nil)
        #expect(alert(at: date(2026, 3, 3, 10, 6)) == nil)
    }

    @Test func 녹음_중이면_켜지_않는다() {
        #expect(alert(at: date(2026, 3, 2, 10, 6), isRecording: true) == nil)
    }

    @Test func 같은_과목을_이미_녹음했으면_켜지_않고_다른_과목_녹음은_상관없다() {
        let own = [(subjectID: "자료구조", startedAt: date(2026, 3, 2, 10, 1))]
        #expect(alert(at: date(2026, 3, 2, 10, 6), recorded: own) == nil)
        let early = [(subjectID: "자료구조", startedAt: date(2026, 3, 2, 9, 51))]
        #expect(alert(at: date(2026, 3, 2, 10, 6), recorded: early) == nil)
        let other = [(subjectID: "알고리즘", startedAt: date(2026, 3, 2, 10, 1))]
        #expect(alert(at: date(2026, 3, 2, 10, 6), recorded: other) != nil)
    }

    @Test func 누르거나_끈_수업은_다시_켜지_않는다() {
        let dismissed: Set<Date> = [date(2026, 3, 2, 10, 0)]
        #expect(alert(at: date(2026, 3, 2, 10, 6), dismissed: dismissed) == nil)
    }

    @Test func 연강은_한_수업으로_보고_첫_칸_시작을_기준으로_한다() {
        // 13:00 시작 연강: 13:05에 켜지고, 14:05(둘째 칸 시작 5분 뒤)에는 새로 켜지지 않는다.
        #expect(alert(at: date(2026, 3, 2, 13, 6))?.classEnd == date(2026, 3, 2, 15, 0))
        #expect(alert(at: date(2026, 3, 2, 14, 6)) == nil)
    }
}
