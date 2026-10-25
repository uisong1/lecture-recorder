import Foundation

/// 알림 하나. 매주 `weekday` `hour:minute`에 되풀이해서 울린다.
public struct ScheduledNotification: Equatable, Sendable {
    public let id: String
    public let title: String
    public let body: String
    public let weekday: Weekday
    public let hour: Int
    public let minute: Int

    public init(id: String, title: String, body: String, weekday: Weekday, hour: Int, minute: Int) {
        self.id = id
        self.title = title
        self.body = body
        self.weekday = weekday
        self.hour = hour
        self.minute = minute
    }
}

/// 시스템 알림. 테스트에서는 가짜 구현을 쓴다.
@MainActor
public protocol NotificationScheduling: AnyObject {
    /// 알림 권한을 요청한다. 이미 정했다면 다시 묻지 않고 그 결과를 돌려준다.
    func requestAuthorization() async -> Bool
    /// 앱이 예약한 알림을 모두 지우고 `notifications`로 바꾼다.
    func replaceAll(with notifications: [ScheduledNotification]) async
    /// 지금 바로 알림 하나를 보낸다. 권한이 없으면 아무 일도 하지 않는다 (새로 묻지 않는다).
    /// `identifier`가 같은 알림은 서로 덮어쓰므로 종류마다 다르게 준다. 알림을 누르면 앱이 열린다.
    func notify(title: String, body: String, identifier: String) async
}

extension NotificationScheduling {
    /// 수업 종료 후 녹음 중 안내처럼 식별자를 따로 정하지 않는 알림.
    public func notify(title: String, body: String) async {
        await notify(title: title, body: body, identifier: "class-overrun")
    }
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

    public init(
        context: ModelContext,
        notifications: any NotificationScheduling,
        defaults: UserDefaults = .standard,
        leadMinutes: Int = ClassSchedule<String>.defaultReminderLeadMinutes
    ) {
        self.context = context
        self.notifications = notifications
        self.defaults = defaults
        self.leadMinutes = leadMinutes
        isEnabled = defaults.bool(forKey: Self.defaultsKey)
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
        await notifications.replaceAll(with: plannedNotifications())
    }

    /// 지금 시간표로 만든 알림 목록.
    public func plannedNotifications() -> [ScheduledNotification] {
        let slots: [TimeSlot]
        do {
            slots = try context.fetch(FetchDescriptor<TimeSlot>())
        } catch {
            Log.data.error("알림용 시간표 조회 실패: \(error.localizedDescription, privacy: .public)")
            return []
        }
        let names = Dictionary(
            slots.compactMap { slot in slot.subject.map { ($0.persistentModelID, $0.name) } },
            uniquingKeysWith: { first, _ in first }
        )
        let schedule = ClassSchedule(entries: slots.compactMap { slot -> ClassSchedule<PersistentIdentifier>.Entry? in
            guard let period = slot.period, let subject = slot.subject else { return nil }
            return .init(period: period, subjectID: subject.persistentModelID)
        })
        return schedule.weeklyReminders(leadMinutes: leadMinutes).map { reminder in
            let name = names[reminder.subjectID] ?? ""
            return ScheduledNotification(
                id: "class-reminder-\(reminder.weekday.rawValue)-\(reminder.time.minutesSinceMidnight)",
                title: Self.title,
                body: "\(name) 수업이 곧 시작됩니다. 녹음할까요?",
                weekday: reminder.weekday,
                hour: reminder.time.hour,
                minute: reminder.time.minute
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
    public override init() {
        super.init()
        // 앱이 앞에 있을 때도 알림을 보여 준다.
        UNUserNotificationCenter.current().delegate = self
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
            let components = DateComponents(hour: notification.hour, minute: notification.minute, weekday: notification.weekday.rawValue)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
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
