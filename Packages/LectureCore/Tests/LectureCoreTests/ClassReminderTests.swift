import Foundation
import Testing
@testable import LectureCore

@Suite struct ClassReminderPlanningTests {
    private func schedule(_ entries: [(Weekday, (Int, Int), (Int, Int), String)]) throws -> ClassSchedule<String> {
        ClassSchedule(entries: try entries.map { .init(period: try period($0.0, $0.1, $0.2), subjectID: $0.3) })
    }

    @Test func 수업_시작_2분_전에_알린다() throws {
        let reminders = try schedule([(.monday, (10, 30), (11, 45), "자료구조")]).weeklyReminders()
        #expect(reminders.count == 1)
        #expect(reminders[0].weekday == .monday)
        #expect(reminders[0].time.description == "10:28")
        #expect(reminders[0].classStart.description == "10:30")
    }

    @Test func 시간표가_비었으면_알림이_없다() {
        #expect(ClassSchedule<String>().weeklyReminders().isEmpty)
    }

    @Test func 요일과_시각_순으로_정렬한다() throws {
        let reminders = try schedule([
            (.friday, (13, 0), (16, 0), "실험"),
            (.monday, (10, 30), (11, 45), "자료구조"),
            (.monday, (9, 0), (10, 15), "운영체제"),
        ]).weeklyReminders()
        #expect(reminders.map(\.subjectID) == ["운영체제", "자료구조", "실험"])
    }

    @Test func 연강은_수업마다_알린다() throws {
        let reminders = try schedule([
            (.monday, (9, 0), (10, 0), "운영체제"),
            (.monday, (10, 0), (11, 0), "자료구조"),
        ]).weeklyReminders()
        #expect(reminders.map(\.time.description) == ["08:58", "09:58"])
    }

    @Test func 같은_과목이_이어진_칸은_한_번만_알린다() throws {
        let reminders = try schedule([
            (.friday, (13, 0), (14, 0), "실험"),
            (.friday, (14, 0), (16, 0), "실험"),
        ]).weeklyReminders()
        #expect(reminders.map(\.classStart.description) == ["13:00"])
    }

    @Test func 쉬는_시간을_두고_다시_시작하는_같은_과목은_각각_알린다() throws {
        let reminders = try schedule([
            (.friday, (9, 0), (10, 0), "실험"),
            (.friday, (10, 15), (11, 0), "실험"),
        ]).weeklyReminders()
        #expect(reminders.count == 2)
    }

    @Test func 자정_직후_수업은_전날_밤에_알린다() throws {
        let reminders = try schedule([(.monday, (0, 1), (1, 0), "새벽")]).weeklyReminders()
        #expect(reminders[0].weekday == .sunday)
        #expect(reminders[0].time.description == "23:59")
    }

    @Test func 여유_분을_바꿀_수_있고_0이면_정각에_알린다() throws {
        let s = try schedule([(.monday, (10, 30), (11, 45), "자료구조")])
        #expect(s.weeklyReminders(leadMinutes: 5)[0].time.description == "10:25")
        #expect(s.weeklyReminders(leadMinutes: 0)[0].time.description == "10:30")
    }

    // MARK: 다음 알림 시각 (2026-03-02는 월요일)

    @Test func 오늘_아직_안_지났으면_오늘_울린다() throws {
        let reminder = try #require(try schedule([(.monday, (10, 30), (11, 45), "자료구조")]).weeklyReminders().first)
        let next = reminder.nextFireDate(after: date(2026, 3, 2, 9, 0), calendar: seoulCalendar)
        #expect(next == date(2026, 3, 2, 10, 28))
    }

    @Test func 정각에_이미_울렸으면_다음_주다() throws {
        let reminder = try #require(try schedule([(.monday, (10, 30), (11, 45), "자료구조")]).weeklyReminders().first)
        let next = reminder.nextFireDate(after: date(2026, 3, 2, 10, 28), calendar: seoulCalendar)
        #expect(next == date(2026, 3, 9, 10, 28))
    }

    @Test func 다른_요일이면_그_요일로_넘어간다() throws {
        let reminder = try #require(try schedule([(.wednesday, (10, 30), (11, 45), "자료구조")]).weeklyReminders().first)
        let next = reminder.nextFireDate(after: date(2026, 3, 2, 12, 0), calendar: seoulCalendar)
        #expect(next == date(2026, 3, 4, 10, 28))
    }

    @Test func 월요일_자정_직후_수업의_알림은_일요일_밤에_울린다() throws {
        let reminder = try #require(try schedule([(.monday, (0, 1), (1, 0), "새벽")]).weeklyReminders().first)
        let next = reminder.nextFireDate(after: date(2026, 3, 2, 12, 0), calendar: seoulCalendar)
        #expect(next == date(2026, 3, 8, 23, 59))
    }
}

@Test func 전날은_일요일_앞이_토요일이고_월요일_앞이_일요일이다() {
    #expect(Weekday.monday.previous == .sunday)
    #expect(Weekday.sunday.previous == .saturday)
    #expect(Weekday.wednesday.previous == .tuesday)
}

#if canImport(SwiftData)
import SwiftData

@MainActor
final class FakeNotificationScheduler: NotificationScheduling {
    var authorized = true
    private(set) var authorizationRequests = 0
    private(set) var scheduled: [ScheduledNotification] = []
    private(set) var replaceCount = 0
    private(set) var notified: [(title: String, body: String)] = []
    private(set) var notifiedIdentifiers: [String] = []
    private var responseHandler: (@MainActor @Sendable (NotificationResponse) async -> Void)?

    func setResponseHandler(_ handler: (@MainActor @Sendable (NotificationResponse) async -> Void)?) {
        responseHandler = handler
    }

    /// 사용자가 알림에 반응한 것처럼 흉내 낸다.
    func simulate(_ response: NotificationResponse) async {
        await responseHandler?(response)
    }

    /// 권한을 허용하지 않았으면 실제 구현처럼 조용히 아무것도 보내지 않는다.
    func notify(title: String, body: String, identifier: String) async {
        guard authorized else { return }
        notified.append((title, body))
        notifiedIdentifiers.append(identifier)
    }

    func requestAuthorization() async -> Bool {
        authorizationRequests += 1
        return authorized
    }

    func replaceAll(with notifications: [ScheduledNotification]) async {
        replaceCount += 1
        scheduled = notifications
    }
}

@MainActor
@Suite struct ClassReminderControllerTests {
    let container: ModelContainer
    let notifications = FakeNotificationScheduler()
    let defaults: UserDefaults
    let controller: ClassReminderController

    init() throws {
        container = try LectureModelContainer.make(inMemory: true)
        let suite = "ClassReminderControllerTests-\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        // 오늘 남은 수업 알림(3-66)이 섞이지 않도록 일요일 밤으로 고정한다.
        controller = ClassReminderController(
            context: container.mainContext,
            notifications: notifications,
            defaults: defaults,
            calendar: seoulCalendar,
            now: { date(2026, 3, 1, 23, 59) }
        )
    }

    private func addClass(_ name: String, _ weekday: Weekday, hour: Int, minute: Int = 0, endHour: Int) throws -> Subject {
        let subject = try SubjectManager(context: container.mainContext).add(name: name, color: .green)
        try ScheduleManager(context: container.mainContext)
            .add(subject: subject, weekday: weekday, start: TimeOfDay(hour: hour, minute: minute), end: TimeOfDay(hour: endHour))
        return subject
    }

    @Test func 기본은_꺼져_있고_아무것도_예약하지_않는다() async throws {
        _ = try addClass("자료구조", .monday, hour: 10, endHour: 11)
        #expect(!controller.isEnabled)
        await controller.reschedule()
        #expect(notifications.replaceCount == 0)
        #expect(notifications.authorizationRequests == 0)
    }

    @Test func 켜면_권한을_요청하고_시간표대로_예약한다() async throws {
        _ = try addClass("자료구조", .monday, hour: 10, minute: 30, endHour: 12)
        await controller.setEnabled(true)
        #expect(controller.isEnabled)
        #expect(controller.message == nil)
        #expect(notifications.authorizationRequests == 1)
        #expect(notifications.scheduled.count == 1)
        let notification = try #require(notifications.scheduled.first)
        #expect(notification.body == "자료구조 수업이 곧 시작됩니다. 녹음할까요?")
        #expect(notification.weekday == .monday)
        #expect(notification.hour == 10 && notification.minute == 28)
    }

    @Test func 권한을_거부하면_꺼진_채로_이유를_알린다() async throws {
        _ = try addClass("자료구조", .monday, hour: 10, endHour: 11)
        notifications.authorized = false
        await controller.setEnabled(true)
        #expect(!controller.isEnabled)
        #expect(controller.message != nil)
        #expect(notifications.scheduled.isEmpty)
        #expect(!defaults.bool(forKey: ClassReminderController.defaultsKey))
    }

    @Test func 끄면_예약을_모두_지운다() async throws {
        _ = try addClass("자료구조", .monday, hour: 10, endHour: 11)
        await controller.setEnabled(true)
        await controller.setEnabled(false)
        #expect(!controller.isEnabled)
        #expect(notifications.scheduled.isEmpty)
    }

    @Test func 시간표가_바뀌면_예약을_다시_만든다() async throws {
        _ = try addClass("자료구조", .monday, hour: 10, endHour: 11)
        await controller.setEnabled(true)
        _ = try addClass("운영체제", .tuesday, hour: 9, endHour: 10)
        await controller.reschedule()
        #expect(notifications.scheduled.count == 2)

        let schedule = ScheduleManager(context: container.mainContext)
        try schedule.delete(try #require(schedule.slots.first))
        await controller.reschedule()
        #expect(notifications.scheduled.count == 1)
    }

    @Test func 켜둔_설정은_다시_실행해도_유지된다() async throws {
        await controller.setEnabled(true)
        let again = ClassReminderController(context: container.mainContext, notifications: notifications, defaults: defaults)
        #expect(again.isEnabled)
    }

    @Test func 시간표가_비었으면_예약이_비어_있다() async throws {
        await controller.setEnabled(true)
        #expect(notifications.scheduled.isEmpty)
    }
}

@MainActor
final class FakeReminderRecordingStarter: ReminderRecordingStarting {
    var outcome: ReminderStartOutcome = .started
    private(set) var requestedSubjects: [String] = []

    func startRecording(forSubjectNamed subjectName: String) async -> ReminderStartOutcome {
        requestedSubjects.append(subjectName)
        return outcome
    }
}

@MainActor
@Suite struct ClassReminderResponseTests {
    let container: ModelContainer
    let notifications = FakeNotificationScheduler()
    let starter = FakeReminderRecordingStarter()
    let defaults: UserDefaults
    let controller: ClassReminderController
    let frontCalls: Counter

    @MainActor
    final class Counter {
        var count = 0
    }

    init() throws {
        container = try LectureModelContainer.make(inMemory: true)
        defaults = try #require(UserDefaults(suiteName: "ClassReminderResponseTests-\(UUID().uuidString)"))
        let calls = Counter()
        frontCalls = calls
        controller = ClassReminderController(
            context: container.mainContext,
            notifications: notifications,
            defaults: defaults,
            recordingStarter: starter,
            bringAppToFront: { calls.count += 1 },
            calendar: seoulCalendar,
            now: { date(2026, 3, 1, 23, 59) }
        )
    }

    @Test func 알림에는_과목_이름이_실려_녹음_시작_버튼이_붙는다() async throws {
        let subject = try SubjectManager(context: container.mainContext).add(name: "자료구조", color: .green)
        try ScheduleManager(context: container.mainContext)
            .add(subject: subject, weekday: .monday, start: TimeOfDay(hour: 10), end: TimeOfDay(hour: 11))
        await controller.setEnabled(true)
        #expect(notifications.scheduled.first?.subjectName == "자료구조")
    }

    @Test func 녹음_시작_버튼을_누르면_알림의_과목으로_시작한다() async {
        await notifications.simulate(.startRecording(subjectName: "자료구조"))
        #expect(starter.requestedSubjects == ["자료구조"])
        #expect(frontCalls.count == 0)
    }

    @Test func 이미_녹음_중이면_조용히_넘어간다() async {
        starter.outcome = .alreadyRecording
        await notifications.simulate(.startRecording(subjectName: "자료구조"))
        #expect(starter.requestedSubjects == ["자료구조"])
        #expect(frontCalls.count == 0)
    }

    @Test func 과목이_지워진_알림은_앱을_앞으로_가져온다() async {
        starter.outcome = .subjectMissing
        await notifications.simulate(.startRecording(subjectName: "지워진 과목"))
        #expect(frontCalls.count == 1)
    }

    @Test func 시작하지_못하면_앱을_앞으로_가져온다() async {
        starter.outcome = .failed
        await notifications.simulate(.startRecording(subjectName: "자료구조"))
        #expect(frontCalls.count == 1)
    }

    @Test func 과목이_적히지_않은_버튼은_녹음하지_않고_앱을_앞으로_가져온다() async {
        await notifications.simulate(.startRecording(subjectName: nil))
        #expect(starter.requestedSubjects.isEmpty)
        #expect(frontCalls.count == 1)
    }

    @Test func 알림_본문을_누르면_앱만_열고_녹음하지_않는다() async {
        await notifications.simulate(.open)
        #expect(starter.requestedSubjects.isEmpty)
        #expect(frontCalls.count == 0)
    }
}
#endif
