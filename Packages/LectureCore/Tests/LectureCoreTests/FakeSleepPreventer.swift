import Foundation
@testable import LectureCore

@MainActor
final class FakeSleepPreventer: SleepPreventing {
    private(set) var isActive = false
    private(set) var beginCount = 0
    private(set) var lastReason: String?

    /// true면 잠자기 방지를 켜지 못한 것처럼 false를 돌려준다.
    var fails = false

    func begin(reason: String) -> Bool {
        beginCount += 1
        lastReason = reason
        guard !fails else { return false }
        isActive = true
        return true
    }

    func end() { isActive = false }
}
