#if canImport(SwiftData)
import Foundation
import SwiftData
import Testing
@testable import LectureCore

/// 녹음 중인지를 테스트에서 바꾸는 깃발.
@MainActor
final class RecordingFlag {
    var isRecording = false
}

@MainActor
@Suite struct MissedStartControllerTests {
    let container: ModelContainer
    let notifications = FakeNotificationScheduler()
    let clock = TestClock(date(2026, 3, 2, 9, 0))  // 월요일 아침
    let flag = RecordingFlag()
    let controller: ClassReminderController

    init() throws {
        container = try LectureModelContainer.make(inMemory: true)
        let defaults = try #require(UserDefaults(suiteName: "MissedStartControllerTests-\(UUID().uuidString)"))
        let clock = clock
        let flag = flag
        controller = ClassReminderController(
            context: container.mainContext,
            notifications: notifications,
            defaults: defaults,
            calendar: seoulCalendar,
            now: { clock.now },
            isRecording: { flag.isRecording }
        )
    }

    @discardableResult
    private func addClass(_ name: String, hour: Int, endHour: Int, weekday: Weekday = .monday) throws -> Subject {
        let subject = try SubjectManager(context: container.mainContext).add(name: name, color: .green)
        try ScheduleManager(context: container.mainContext)
            .add(subject: subject, weekday: weekday, start: TimeOfDay(hour: hour), end: TimeOfDay(hour: endHour))
        return subject
    }

    private var oneShots: [ScheduledNotification] { notifications.scheduled.filter { $0.fireDate != nil } }

    @Test func 켜면_오늘_남은_수업마다_시작_5분_뒤_한_번짜리_알림을_예약한다() async throws {
        try addClass("자료구조", hour: 10, endHour: 11)
        await controller.setEnabled(true)

        // 매주 되풀이 알림 하나와 오늘의 한 번짜리 알림 하나.
        #expect(notifications.scheduled.count == 2)
        let missed = try #require(oneShots.first)
        #expect(missed.fireDate == date(2026, 3, 2, 10, 5))
        #expect(missed.body == "자료구조 수업이 시작됐는데 녹음 중이 아닙니다")
        #expect(missed.subjectName == "자료구조")  // "녹음 시작" 버튼이 붙는다
        #expect(missed.hour == 10 && missed.minute == 5 && missed.weekday == .monday)
    }

    @Test func 알림을_끄거나_허용하지_않으면_예약하지_않는다() async throws {
        try addClass("자료구조", hour: 10, endHour: 11)
        await controller.reschedule()
        #expect(notifications.replaceCount == 0)

        notifications.authorized = false
        await controller.setEnabled(true)
        #expect(!controller.isEnabled)
        #expect(notifications.scheduled.isEmpty)
    }

    @Test func 녹음_중이면_예약하지_않고_끝나면_다시_예약한다() async throws {
        try addClass("자료구조", hour: 10, endHour: 11)
        await controller.setEnabled(true)
        #expect(oneShots.count == 1)

        flag.isRecording = true
        await controller.reschedule()
        #expect(oneShots.isEmpty)
        #expect(notifications.scheduled.count == 1)  // 매주 알림은 그대로

        flag.isRecording = false
        await controller.reschedule()
        #expect(oneShots.count == 1)
    }

    @Test func 이미_그_수업을_녹음했으면_예약하지_않는다() async throws {
        let subject = try addClass("자료구조", hour: 10, endHour: 11)
        container.mainContext.insert(Recording(
            title: "자료구조", subject: subject, startedAt: date(2026, 3, 2, 9, 55), duration: 60, relativePath: "a.m4a"
        ))
        try container.mainContext.save()
        await controller.setEnabled(true)
        #expect(oneShots.isEmpty)
    }

    @Test func 다른_과목_녹음은_이_수업의_알림을_없애지_않는다() async throws {
        try addClass("자료구조", hour: 10, endHour: 11)
        let other = try addClass("운영체제", hour: 13, endHour: 14)
        container.mainContext.insert(Recording(
            title: "운영체제", subject: other, startedAt: date(2026, 3, 2, 9, 55), duration: 60, relativePath: "b.m4a"
        ))
        try container.mainContext.save()
        await controller.setEnabled(true)
        #expect(oneShots.compactMap(\.subjectName) == ["자료구조", "운영체제"])
    }

    @Test func 수업이_이미_끝났거나_알림_시각이_지났으면_예약하지_않는다() async throws {
        try addClass("자료구조", hour: 10, endHour: 11)
        clock.advance(by: 65 * 60)  // 10:05 정각
        await controller.setEnabled(true)
        #expect(oneShots.isEmpty)

        clock.advance(by: 3 * 3600)  // 13:05
        await controller.reschedule()
        #expect(oneShots.isEmpty)
    }

    @Test func 다른_요일_수업은_오늘_알림에_넣지_않는다() async throws {
        try addClass("운영체제", hour: 10, endHour: 11, weekday: .tuesday)
        await controller.setEnabled(true)
        #expect(oneShots.isEmpty)
        #expect(notifications.scheduled.count == 1)
    }

    @Test func 시간표를_바꾸고_다시_예약하면_반영된다() async throws {
        try addClass("자료구조", hour: 10, endHour: 11)
        await controller.setEnabled(true)
        #expect(oneShots.count == 1)

        try addClass("알고리즘", hour: 14, endHour: 15)
        await controller.reschedule()
        #expect(oneShots.compactMap(\.subjectName) == ["자료구조", "알고리즘"])
    }

    @Test func 날이_바뀌면_새_날의_수업으로_다시_만든다() async throws {
        try addClass("자료구조", hour: 10, endHour: 11)
        try addClass("운영체제", hour: 10, endHour: 11, weekday: .tuesday)
        await controller.setEnabled(true)
        #expect(oneShots.first?.fireDate == date(2026, 3, 2, 10, 5))

        clock.advance(by: 24 * 3600)  // 화요일
        await controller.reschedule()
        #expect(oneShots.compactMap(\.subjectName) == ["운영체제"])
        #expect(oneShots.first?.fireDate == date(2026, 3, 3, 10, 5))
    }
}
#endif
