import Foundation

/// 녹음하는 동안 맥이 잠자기에 들어가지 않게 막는다. 테스트에서는 가짜 구현을 쓴다.
@MainActor
public protocol SleepPreventing: AnyObject {
    /// 잠자기 방지를 시작한다. 이미 켜져 있으면 아무 일도 하지 않는다.
    func begin(reason: String)
    /// 잠자기 방지를 끈다. 켜져 있지 않으면 아무 일도 하지 않는다.
    func end()
}

#if canImport(IOKit)
import IOKit.pwr_mgt

/// IOKit 전원 어서션으로 시스템 유휴 잠자기를 막는 구현. 화면은 꺼질 수 있다.
@MainActor
public final class SystemSleepPreventer: SleepPreventing {
    private var assertionID: IOPMAssertionID?

    public init() {}

    public func begin(reason: String) {
        guard assertionID == nil else { return }
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id
        )
        if result == kIOReturnSuccess {
            assertionID = id
        } else {
            Log.recording.error("잠자기 방지 실패: IOReturn \(result, privacy: .public)")
        }
    }

    public func end() {
        guard let id = assertionID else { return }
        assertionID = nil
        IOPMAssertionRelease(id)
    }
}
#endif
