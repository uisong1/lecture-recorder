import Foundation

/// 배터리와 전원 연결 상태.
public struct PowerStatus: Equatable, Sendable {
    /// 배터리 잔량(0...100).
    public let batteryPercent: Int
    /// 전원(충전기)에 연결되어 있는지. 충전 중이거나 가득 찬 경우 모두 true.
    public let isPluggedIn: Bool

    public init(batteryPercent: Int, isPluggedIn: Bool) {
        self.batteryPercent = batteryPercent
        self.isPluggedIn = isPluggedIn
    }
}

/// 전원 상태를 알려 주는 곳. 테스트에서는 가짜 구현을 쓴다.
@MainActor
public protocol PowerStatusProviding: AnyObject {
    /// 지금 전원 상태. 배터리가 없는 맥(데스크톱)이거나 알 수 없으면 nil.
    func current() -> PowerStatus?
}

/// 배터리 상태에 따른 안내 문구.
public enum BatteryAdvice {
    /// 이 잔량(%) 미만이고 전원이 연결되지 않았으면 녹음 중 경고한다. 20%는 경고하지 않는다.
    public static let lowBatteryPercent = 20

    /// 녹음 중 화면에 항상 보이는 안내. 덮개를 닫으면 맥이 잠자기에 들어가 녹음이 멈춘다.
    public static let lidNotice = "덮개를 닫으면 녹음이 멈춥니다"

    /// 녹음 중 보여줄 배터리 경고. 전원이 연결되어 있거나 배터리가 없거나 20% 이상이면 nil.
    public static func recordingWarning(for status: PowerStatus?) -> String? {
        guard let status, !status.isPluggedIn, status.batteryPercent < lowBatteryPercent else { return nil }
        return "배터리가 \(status.batteryPercent)%입니다. 충전기를 연결하세요. 배터리가 떨어지면 녹음이 멈춥니다."
    }

    /// 녹음 시작 전 화면에 보여줄 충전 권장. 충전기에 연결되어 있거나 배터리가 없으면 nil.
    public static func preRecordingAdvice(for status: PowerStatus?) -> String? {
        guard let status, !status.isPluggedIn else { return nil }
        return "충전기가 연결되어 있지 않습니다. 3시간 수업이라면 충전기를 연결해 두세요."
    }
}

#if canImport(IOKit)
import IOKit.ps

/// IOKit 전원 정보에서 내장 배터리 상태를 읽는다.
@MainActor
public final class SystemPowerStatus: PowerStatusProviding {
    public init() {}

    public func current() -> PowerStatus? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let capacity = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int,
                  maximum > 0
            else { continue }
            let pluggedIn = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            return PowerStatus(batteryPercent: min(max(capacity * 100 / maximum, 0), 100), isPluggedIn: pluggedIn)
        }
        return nil
    }
}
#endif
