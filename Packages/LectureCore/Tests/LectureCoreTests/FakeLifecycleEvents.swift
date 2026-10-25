import Foundation
@testable import LectureCore

@MainActor
final class FakeLifecycleEvents: LifecycleEventSource {
    private var handlers: [@MainActor (LifecycleEvent) -> Void] = []

    func observe(_ handler: @escaping @MainActor (LifecycleEvent) -> Void) {
        handlers.append(handler)
    }

    func send(_ event: LifecycleEvent) {
        handlers.forEach { $0(event) }
    }
}
