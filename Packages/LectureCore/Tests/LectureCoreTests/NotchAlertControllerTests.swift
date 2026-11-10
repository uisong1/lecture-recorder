#if canImport(SwiftData)
import Foundation
import SwiftData
import Testing
@testable import LectureCore

@MainActor
@Suite struct NotchAlertControllerTests {
    let container: ModelContainer
    let clock = TestClock(date(2026, 3, 2, 9, 0))  // 월요일 아침
    let flag = RecordingFlag()
    let defaults: UserDefaults
    let controller: ClassReminderController

    init() throws {
        container = try LectureModelContainer.make(inMemory: true)
        defaults = try #require(UserDefaults(suiteName: "NotchAlertControllerTests-\(UUID().uuidString)"))
        let clock = clock
        let flag = flag
        controller = ClassReminderController(
            context: container.mainContext,
            notifications: FakeNotificationScheduler(),
            defaults: defaults,
            calendar: seoulCalendar,
            now: { clock.now },
            isRecording: { flag.isRecording }
        )
    }

    @discardableResult
    private func addClass(_ name: String, hour: Int, endHour: Int) throws -> Subject {
        let subject = try SubjectManager(context: container.mainContext).add(name: name, color: .green)
        try ScheduleManager(context: container.mainContext)
            .add(subject: subject, weekday: .monday, start: TimeOfDay(hour: hour), end: TimeOfDay(hour: endHour))
        return subject
    }

    @Test func 기본은_켜져_있고_수업_시작_정각에_불빛이_뜬다() throws {
        try addClass("자료구조", hour: 10, endHour: 11)
        #expect(controller.isNotchAlertEnabled)
        clock.advance(by: 60 * 60 - 1)  // 9:59:59
        controller.refreshNotchAlert()
        #expect(controller.notchAlert == nil)
        clock.advance(by: 1)  // 10:00
        controller.refreshNotchAlert()
        #expect(controller.notchAlert == NotchAlertInfo(subjectName: "자료구조", classStart: date(2026, 3, 2, 10, 0), expiresAt: date(2026, 3, 2, 11, 0)))
    }

    @Test func 누르면_꺼지고_같은_수업에서는_다시_켜지지_않는다() throws {
        try addClass("자료구조", hour: 10, endHour: 11)
        clock.advance(by: 66 * 60)
        controller.refreshNotchAlert()
        #expect(controller.notchAlert != nil)
        controller.dismissNotchAlert()
        #expect(controller.notchAlert == nil)
        controller.refreshNotchAlert()
        #expect(controller.notchAlert == nil)
    }

    @Test func 녹음을_시작하면_꺼지고_이미_녹음한_수업은_켜지지_않는다() throws {
        try addClass("자료구조", hour: 10, endHour: 11)
        clock.advance(by: 66 * 60)
        controller.refreshNotchAlert()
        #expect(controller.notchAlert != nil)
        flag.isRecording = true
        controller.refreshNotchAlert()
        #expect(controller.notchAlert == nil)
    }

    @Test func 끄면_불빛이_사라지고_설정이_저장된다() throws {
        try addClass("자료구조", hour: 10, endHour: 11)
        clock.advance(by: 66 * 60)
        controller.refreshNotchAlert()
        #expect(controller.notchAlert != nil)
        controller.setNotchAlertEnabled(false)
        #expect(controller.notchAlert == nil)
        #expect(defaults.object(forKey: ClassReminderController.notchDefaultsKey) as? Bool == false)
        controller.refreshNotchAlert()
        #expect(controller.notchAlert == nil)
        controller.setNotchAlertEnabled(true)
        #expect(controller.notchAlert != nil)
    }

    @Test func 시간이_지나도_누르기_전에는_계속_켜져_있고_수업이_끝나면_꺼진다() throws {
        try addClass("자료구조", hour: 10, endHour: 11)
        clock.advance(by: 66 * 60)  // 10:06
        controller.refreshNotchAlert()
        clock.advance(by: 40 * 60)  // 10:46
        controller.refreshNotchAlert()
        #expect(controller.notchAlert != nil)
        clock.advance(by: 14 * 60)  // 11:00
        controller.refreshNotchAlert()
        #expect(controller.notchAlert == nil)
    }
}
#endif
