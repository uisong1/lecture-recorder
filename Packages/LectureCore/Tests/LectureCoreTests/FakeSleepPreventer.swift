import Foundation
@testable import LectureCore

@MainActor
final class FakeSleepPreventer: SleepPreventing {
    private(set) var isActive = false
    private(set) var beginCount = 0
    private(set) var lastReason: String?

    func begin(reason: String) {
        beginCount += 1
        lastReason = reason
        isActive = true
    }

    func end() { isActive = false }
}
