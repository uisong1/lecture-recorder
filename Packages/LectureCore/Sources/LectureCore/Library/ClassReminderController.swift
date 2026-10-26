import Foundation

/// 알림 하나. 매주 `weekday` `hour:minute`에 되풀이해서 울린다. `fireDate`가 있으면 그 시각에 한 번만 울린다.
public struct ScheduledNotification: Equatable, Sendable {
    public let id: String
    public let title: String
    public let body: String
    public let weekday: Weekday
    public let hour: Int
    public let minute: Int
    /// 이 알림이 알리는 수업의 과목 이름. 있으면 알림에 "녹음 시작" 버튼이 붙는다.
    public let subjectName: String?
    /// 있으면 되풀이하지 않고 이 시각에 한 번만 울린다 (요일·시각은 이 시각에서 따온 값).
    public let fireDate: Date?

    public init(id: String, title: String, body: String, weekday: Weekday, hour: Int, minute: Int, subjectName: String? = nil, fireDate: Date? = nil) {
        self.subjectName = subjectName
        self.fireDate = fireDate
        self.id = id
        self.title = title
        self.body = body
        self.weekday = weekday
        self.hour = hour
        self.minute = minute
    }
}

/// 사용자가 알림에 한 반응.
public enum NotificationResponse: Equatable, Sendable {
    /// 알림 본문을 눌렀다. 앱이 열리는 것 말고는 할 일이 없다.
    case open
    /// 알림의 "녹음 시작" 버튼을 눌렀다. `subjectName`은 알림에 적힌 과목(없으면 nil).
    case startRecording(subjectName: String?)
}

/// 시스템 알림. 테스트에서는 가짜 구현을 쓴다.
@MainActor
public protocol NotificationScheduling: AnyObject {
    /// 알림에 대한 반응을 받을 곳을 정한다. nil이면 반응을 무시한다.
    func setResponseHandler(_ handler: (@MainActor @Sendable (NotificationResponse) async -> Void)?)
    /// 알림 권한을 요청한다. 이미 정했다면 다시 묻지 않고 그 결과를 돌려준다.
    func requestAuthorization() async -> Bool
    /// 앱이 예약한 알림을 모두 지우고 `notifications`로 바꾼다.
    func replaceAll(with notifications: [ScheduledNotification]) async
    /// 지금 바로 알림 하나를 보낸다. 권한이 없으면 아무 일도 하지 않는다 (새로 묻지 않는다).
    /// `identifier`가 같은 알림은 서로 덮어쓰므로 종류마다 다르게 준다. 알림을 누르면 앱이 열린다.
    func notify(title: String, body: String, identifier: String) async
}

extension NotificationScheduling {
    /// 반응을 받지 않는 구현(미리보기 등)은 아무것도 하지 않는다.
    public func setResponseHandler(_ handler: (@MainActor @Sendable (NotificationResponse) async -> Void)?) {}

    /// 수업 종료 후 녹음 중 안내처럼 식별자를 따로 정하지 않는 알림.
    public func notify(title: String, body: String) async {
        await notify(title: title, body: body, identifier: "class-overrun")
    }
}

/// 알림의 "녹음 시작" 버튼이 녹음을 시작하는 쪽. 녹음 컨트롤러가 구현하고 테스트에서는 가짜를 쓴다.
@MainActor
public protocol ReminderRecordingStarting: AnyObject {
    /// 이름이 `subjectName`인 과목으로 녹음을 시작한다. 이미 녹음 중이면 아무것도 하지 않는다.
    func startRecording(forSubjectNamed subjectName: String) async -> ReminderStartOutcome
}

/// 알림 버튼으로 녹음을 시작해 본 결과.
public enum ReminderStartOutcome: Equatable, Sendable {
    case started
    /// 이미 녹음 중이라 아무것도 하지 않았다.
    case alreadyRecording
    /// 알림에 적힌 과목이 지워졌거나 이름이 바뀌었다.
    case subjectMissing
    /// 녹음을 시작하지 못했다 (마이크 권한 없음 등). 이유는 녹음 화면에 보인다.
    case failed
}

#if canImport(SwiftData)
import Observation
import SwiftData

/// 수업 시작 알림을 켜고 끄고, 시간표에 맞춰 예약을 다시 만든다. 알림은 안내일 뿐 녹음을 시작하지 않는다.
@MainActor
@Observable
public final class ClassReminderController {
    public static let defaultsKey = "classRemindersEnabled"
    public static let title = "수업 시작"

    /// 알림을 켰는지. 기본은 꺼짐.
    public private(set) var isEnabled: Bool
    /// 화면에 보일 안내 (권한 거부 등). 문제가 없으면 nil.
    public private(set) var message: String?

    private let context: ModelContext
    private let notifications: any NotificationScheduling
    private let defaults: UserDefaults
    private let leadMinutes: Int
    /// 알림 버튼으로 녹음을 시작할 곳. 없으면 버튼을 눌러도 아무 일도 없다.
    private let recordingStarter: (any ReminderRecordingStarting)?
    /// 녹음을 시작하지 못했을 때 사용자가 안내를 볼 수 있게 앱을 앞으로 가져온다.
    private let bringAppToFront: @MainActor () -> Void
    private let calendar: Calendar
    private let now: @MainActor () -> Date
    /// 지금 녹음 중인지. 녹음 중에는 "녹음 중이 아닙니다" 알림을 예약하지 않는다.
    private let isRecording: @MainActor () -> Bool

    public init(
        context: ModelContext,
        notifications: any NotificationScheduling,
        defaults: UserDefaults = .standard,
        leadMinutes: Int = ClassSchedule<String>.defaultReminderLeadMinutes,
        recordingStarter: (any ReminderRecordingStarting)? = nil,
        bringAppToFront: @escaping @MainActor () -> Void = {},
        calendar: Calendar = .current,
        now: @escaping @MainActor () -> Date = { Date() },
        isRecording: @escaping @MainActor () -> Bool = { false }
    ) {
        self.calendar = calendar
        self.now = now
        self.isRecording = isRecording
        self.recordingStarter = recordingStarter
        self.bringAppToFront = bringAppToFront
        self.context = context
        self.notifications = notifications
        self.defaults = defaults
        self.leadMinutes = leadMinutes
        isEnabled = defaults.bool(forKey: Self.defaultsKey)
        notifications.setResponseHandler { [weak self] response in
            await self?.handle(response)
        }
    }

    /// 알림에 대한 반응을 처리한다. 본문을 누르면 앱이 열릴 뿐이고, "녹음 시작" 버튼을 눌렀을 때만 녹음을 시작한다.
    /// 이미 녹음 중이면 건드리지 않는다. 시작하지 못하면 앱을 앞으로 가져와 이유를 보여 준다.
    public func handle(_ response: NotificationResponse) async {
        guard case .startRecording(let subjectName) = response, let recordingStarter else { return }
        guard let subjectName else {
            Log.recording.notice("알림에 과목이 없어 녹음을 시작하지 않음")
            bringAppToFront()
            return
        }
        switch await recordingStarter.startRecording(forSubjectNamed: subjectName) {
        case .started, .alreadyRecording:
            break
        case .subjectMissing, .failed:
            bringAppToFront()
        }
    }

    /// 켜거나 끈다. 켤 때 권한이 거부되면 꺼 둔 채로 이유를 알린다. 앱의 다른 기능에는 영향이 없다.
    public func setEnabled(_ enabled: Bool) async {
        if enabled {
            guard await notifications.requestAuthorization() else {
                Log.data.notice("알림 권한 없음, 수업 시작 알림을 켜지 않음")
                isEnabled = false
                defaults.set(false, forKey: Self.defaultsKey)
                message = "알림 권한이 꺼져 있어 알려 드릴 수 없습니다. 시스템 설정 > 알림에서 허용해 주세요."
                return
            }
            isEnabled = true
            defaults.set(true, forKey: Self.defaultsKey)
            message = nil
            await reschedule()
        } else {
            isEnabled = false
            defaults.set(false, forKey: Self.defaultsKey)
            message = nil
            await notifications.replaceAll(with: [])
        }
    }

    /// 시간표나 과목 이름이 바뀌었을 때 예약을 다시 만든다. 꺼져 있으면 아무 일도 하지 않는다.
    public func reschedule() async {
        guard isEnabled else { return }
        await notifications.replaceAll(with: plannedNotifications() + plannedMissedStartNotifications())
    }

    /// 시간표와 과목 이름. 읽지 못하면 nil.
    private func loadSchedule() -> (schedule: ClassSchedule<PersistentIdentifier>, names: [PersistentIdentifier: String])? {
        let slots: [TimeSlot]
        do {
            slots = try context.fetch(FetchDescriptor<TimeSlot>())
        } catch {
            Log.data.error("알림용 시간표 조회 실패: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let names = Dictionary(
            slots.compactMap { slot in slot.subject.map { ($0.persistentModelID, $0.name) } },
            uniquingKeysWith: { first, _ in first }
        )
        let schedule = ClassSchedule(entries: slots.compactMap { slot -> ClassSchedule<PersistentIdentifier>.Entry? in
            guard let period = slot.period, let subject = slot.subject else { return nil }
            return .init(period: period, subjectID: subject.persistentModelID)
        })
        return (schedule, names)
    }

    /// 오늘 시작한 녹음의 과목. 이미 녹음한 수업인지 가릴 때 쓴다.
    private func todaysRecordings() -> [(subjectID: PersistentIdentifier, startedAt: Date)] {
        let dayStart = calendar.startOfDay(for: now())
        do {
            let recordings = try context.fetch(FetchDescriptor<Recording>(predicate: #Predicate { $0.startedAt >= dayStart }))
            return recordings.compactMap { recording in
                recording.subject.map { (subjectID: $0.persistentModelID, startedAt: recording.startedAt) }
            }
        } catch {
            Log.data.error("알림용 오늘 녹음 조회 실패: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// 오늘 남은 수업 중 시작 5분 뒤에도 녹음 중이 아니면 보낼 한 번짜리 알림 목록.
    /// 지금 녹음 중이면 비어 있다 (녹음이 끝나면 `reschedule()`로 다시 만든다).
    public func plannedMissedStartNotifications() -> [ScheduledNotification] {
        guard !isRecording(), let (schedule, names) = loadSchedule() else { return [] }
        let current = now()
        return schedule.missedStartReminders(now: current, calendar: calendar, recorded: todaysRecordings()).compactMap { reminder in
            guard let name = names[reminder.subjectID], !name.isEmpty else { return nil }
            let parts = calendar.dateComponents([.weekday, .hour, .minute], from: reminder.fireDate)
            guard let weekdayValue = parts.weekday, let weekday = Weekday(rawValue: weekdayValue),
                  let hour = parts.hour, let minute = parts.minute
            else { return nil }
            return ScheduledNotification(
                id: "missed-start-\(Int(reminder.fireDate.timeIntervalSince1970))",
                title: Self.title,
                body: "\(name) 수업이 시작됐는데 녹음 중이 아닙니다",
                weekday: weekday,
                hour: hour,
                minute: minute,
                subjectName: name,
                fireDate: reminder.fireDate
            )
        }
    }

    /// 지금 시간표로 만든 매주 되풀이 알림 목록.
    public func plannedNotifications() -> [ScheduledNotification] {
        guard let (schedule, names) = loadSchedule() else { return [] }
        return schedule.weeklyReminders(leadMinutes: leadMinutes).map { reminder in
            let name = names[reminder.subjectID] ?? ""
            return ScheduledNotification(
                id: "class-reminder-\(reminder.weekday.rawValue)-\(reminder.time.minutesSinceMidnight)",
                title: Self.title,
                body: "\(name) 수업이 곧 시작됩니다. 녹음할까요?",
                weekday: reminder.weekday,
                hour: reminder.time.hour,
                minute: reminder.time.minute,
                subjectName: name.isEmpty ? nil : name
            )
        }
    }
}
#endif

#if canImport(UserNotifications)
import UserNotifications

/// `UNUserNotificationCenter`로 매주 되풀이되는 알림을 예약한다. 알림을 누르면 앱이 열린다.
@MainActor
public final class SystemNotificationScheduler: NSObject, NotificationScheduling, UNUserNotificationCenterDelegate {
    nonisolated static let categoryID = "class-reminder"
    nonisolated static let startActionID = "start-recording"
    nonisolated static let subjectNameKey = "subjectName"

    private var responseHandler: (@MainActor @Sendable (NotificationResponse) async -> Void)?

    public override init() {
        super.init()
        // 앱이 앞에 있을 때도 알림을 보여 준다.
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        // 버튼을 눌러야만 녹음이 시작된다. 앱을 앞으로 가져오지 않는다(.foreground 없음).
        let start = UNNotificationAction(identifier: Self.startActionID, title: "녹음 시작", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.categoryID, actions: [start], intentIdentifiers: [])
        ])
    }

    public func setResponseHandler(_ handler: (@MainActor @Sendable (NotificationResponse) async -> Void)?) {
        responseHandler = handler
    }

    private func respond(_ response: NotificationResponse) async {
        await responseHandler?(response)
    }

    public func requestAuthorization() async -> Bool {
        await Self.authorize()
    }

    public func replaceAll(with notifications: [ScheduledNotification]) async {
        await Self.replace(with: notifications)
    }

    public func notify(title: String, body: String, identifier: String) async {
        await Self.deliver(title: title, body: body, identifier: identifier)
    }

    // 알림 센터는 메인 액터 밖에서 쓴다 (센터 객체를 액터 사이로 넘기지 않는다).
    nonisolated private static func authorize() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            Log.data.error("알림 권한 요청 실패: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    nonisolated private static func replace(with notifications: [ScheduledNotification]) async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        for notification in notifications {
            let content = UNMutableNotificationContent()
            content.title = notification.title
            content.body = notification.body
            content.sound = .default
            if let subjectName = notification.subjectName {
                content.categoryIdentifier = Self.categoryID
                content.userInfo = [Self.subjectNameKey: subjectName]
            }
            let trigger: UNCalendarNotificationTrigger
            if let fireDate = notification.fireDate {
                // 한 번만 울린다. 날짜까지 정해서 내일 같은 시각에 다시 울리지 않게 한다.
                let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
                trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            } else {
                let components = DateComponents(hour: notification.hour, minute: notification.minute, weekday: notification.weekday.rawValue)
                trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            }
            do {
                try await center.add(UNNotificationRequest(identifier: notification.id, content: content, trigger: trigger))
            } catch {
                Log.data.error("알림 예약 실패 \(notification.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    nonisolated private static func deliver(title: String, body: String, identifier: String) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        do {
            try await center.add(request)
        } catch {
            Log.data.error("알림 전송 실패: \(error.localizedDescription, privacy: .public)")
        }
    }

    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let subjectName = response.notification.request.content.userInfo[Self.subjectNameKey] as? String
        let parsed: NotificationResponse = response.actionIdentifier == Self.startActionID
            ? .startRecording(subjectName: subjectName)
            : .open
        await respond(parsed)
    }
}
#endif

/// 알림을 아무것도 하지 않는 구현. UI 테스트와 미리보기에서 쓴다.
@MainActor
public final class NoNotificationScheduler: NotificationScheduling {
    public init() {}
    public func requestAuthorization() async -> Bool { true }
    public func replaceAll(with notifications: [ScheduledNotification]) async {}
    public func notify(title: String, body: String, identifier: String) async {}
}
