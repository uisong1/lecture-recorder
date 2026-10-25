import Foundation

/// 녹음에 영향을 주는 시스템 이벤트.
public enum LifecycleEvent: Sendable, Equatable {
    /// 맥이 잠자기에 들어가기 직전.
    case willSleep
    /// 맥이 잠자기에서 깨어남.
    case didWake
    /// 앱이 종료되기 직전.
    case willTerminate
}

/// 잠자기·종료 이벤트를 알려 주는 곳. 테스트에서는 가짜 구현을 쓴다.
@MainActor
public protocol LifecycleEventSource: AnyObject {
    /// 이벤트가 오면 `handler`를 메인 스레드에서 동기적으로 부른다.
    func observe(_ handler: @escaping @MainActor (LifecycleEvent) -> Void)
}

#if canImport(AppKit)
import AppKit

/// `NSWorkspace`와 `NSApplication` 알림을 이벤트로 바꾼다. 앱 수명 동안 쓰는 객체라 관찰을 해제하지 않는다.
@MainActor
public final class SystemLifecycleEvents: LifecycleEventSource {
    public init() {}

    public func observe(_ handler: @escaping @MainActor (LifecycleEvent) -> Void) {
        let workspace = NSWorkspace.shared.notificationCenter
        let pairs: [(NotificationCenter, Notification.Name, LifecycleEvent)] = [
            (workspace, NSWorkspace.willSleepNotification, .willSleep),
            (workspace, NSWorkspace.didWakeNotification, .didWake),
            (.default, NSApplication.willTerminateNotification, .willTerminate),
        ]
        for (center, name, event) in pairs {
            // 알림이 메인 큐로 오므로 그 자리에서 동기적으로 처리한다 (종료 직전에는 기다려 주지 않는다).
            _ = center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { handler(event) }
            }
        }
    }
}
#endif
