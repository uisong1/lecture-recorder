import Foundation

/// 소리가 나가는 곳의 종류. 맥 내장 스피커는 소리가 마이크로 되돌아와 녹음에 섞인다.
public enum AudioOutputKind: Equatable, Sendable {
    /// 맥 내장 스피커.
    case builtInSpeaker
    /// 이어폰·헤드폰(3.5mm 단자, 블루투스, USB 등) 같은 외부 출력.
    case external
    /// 알 수 없거나 스피커일 수 있는 출력 (HDMI 모니터 등).
    case unknown
}

/// 지금 소리가 나가는 곳을 알려 주는 곳. 테스트에서는 가짜 구현을 쓴다.
@MainActor
public protocol AudioOutputInspecting: AnyObject {
    func currentOutput() -> AudioOutputKind
}

/// 녹음 중에 재생을 시작해도 되는지 판단한다.
public enum RecordingPlaybackGuard {
    /// 녹음 중(일시정지 포함)이고, 이어폰·외부 출력이 아니라고 확신할 수 없을 때만 확인이 필요하다.
    public static func needsConfirmation(isRecording: Bool, output: AudioOutputKind) -> Bool {
        guard isRecording else { return false }
        return output != .external
    }

    public static let confirmationTitle = "지금 녹음 중이에요"
    public static let confirmationMessage = "지금 녹음 중이라 재생 소리가 녹음에 들어갈 수 있어요. 이어폰을 연결하거나 녹음이 끝난 뒤에 들어 주세요."
    public static let confirmButton = "그래도 재생"
}

#if canImport(CoreAudio)
import CoreAudio

/// CoreAudio의 기본 출력 장치로 소리가 나가는 곳을 판별한다.
@MainActor
public final class SystemAudioOutput: AudioOutputInspecting {
    public init() {}

    public func currentOutput() -> AudioOutputKind {
        Self.defaultOutput()
    }

    nonisolated private static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    nonisolated private static func uint32(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> UInt32? {
        var address = address
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    nonisolated private static func defaultOutput() -> AudioOutputKind {
        guard let device = uint32(AudioObjectID(kAudioObjectSystemObject), address(kAudioHardwarePropertyDefaultOutputDevice)),
              device != kAudioObjectUnknown,
              let transport = uint32(device, address(kAudioDevicePropertyTransportType))
        else { return .unknown }
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn:
            // 내장 출력은 스피커와 3.5mm 헤드폰 단자가 같은 장치이고, 데이터 소스로 구분한다.
            let source = uint32(device, address(kAudioDevicePropertyDataSource, scope: kAudioDevicePropertyScopeOutput))
            return source == headphonesSource ? .external : .builtInSpeaker
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE, kAudioDeviceTransportTypeUSB, kAudioDeviceTransportTypeAirPlay:
            return .external
        default:
            return .unknown
        }
    }

    /// 'hdpn': 내장 장치의 헤드폰 데이터 소스.
    nonisolated private static let headphonesSource: UInt32 = 0x6864706E
}
#endif
