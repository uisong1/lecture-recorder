import Foundation

/// 마이크 같은 오디오 입력 장치.
public struct AudioInputDevice: Equatable, Sendable {
    /// 장치를 구분하는 고유 값 (이름이 같아도 다른 장치일 수 있다).
    public let id: String
    /// 화면에 보일 이름 ("MacBook Pro 마이크").
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// 입력 장치 상태를 알려 주는 곳. 앱은 시스템 설정의 기본 입력 장치를 따르고, 장치는 고르지 않는다.
/// 테스트에서는 가짜 구현을 쓴다.
@MainActor
public protocol AudioInputMonitoring: AnyObject {
    /// 지금 기본 입력 장치. 입력 장치가 없으면 nil.
    func currentDevice() -> AudioInputDevice?
    /// 기본 입력 장치가 바뀌거나 장치가 연결·해제될 때 `handler`를 메인 스레드에서 부른다.
    func observe(_ handler: @escaping @MainActor () -> Void)
}

/// 녹음 중 입력 장치가 바뀌었는지에 따른 경고 문구.
public enum InputDeviceAdvice {
    /// 녹음을 시작할 때의 장치(`started`)와 지금 장치(`current`)를 비교한다.
    /// 시작할 때 장치를 알 수 없었거나 그대로면 nil. 녹음 기록은 계속되며 경고만 한다.
    public static func warning(started: AudioInputDevice?, current: AudioInputDevice?) -> String? {
        guard let started, started != current else { return nil }
        guard let current else {
            return "마이크 ‘\(started.name)’ 연결이 끊겼습니다. 소리가 녹음되지 않을 수 있으니 마이크를 확인하세요."
        }
        return "입력 마이크가 ‘\(started.name)’에서 ‘\(current.name)’(으)로 바뀌었습니다. 소리가 제대로 들어오는지 확인하세요."
    }
}

#if canImport(CoreAudio)
import CoreAudio

/// CoreAudio의 기본 입력 장치를 읽고, 바뀔 때 알려 준다. 앱 수명 동안 쓰는 객체라 관찰을 해제하지 않는다.
@MainActor
public final class SystemAudioInput: AudioInputMonitoring {
    public init() {}

    public func currentDevice() -> AudioInputDevice? {
        Self.defaultInputDevice()
    }

    public func observe(_ handler: @escaping @MainActor () -> Void) {
        for selector in [kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyDevices] {
            var address = Self.address(selector)
            let status = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main) { _, _ in
                MainActor.assumeIsolated { handler() }
            }
            if status != noErr {
                Log.recording.error("입력 장치 변경 감시 실패: OSStatus \(status, privacy: .public)")
            }
        }
    }

    nonisolated private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    nonisolated private static func defaultInputDevice() -> AudioInputDevice? {
        var address = address(kAudioHardwarePropertyDefaultInputDevice)
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        guard status == noErr, deviceID != kAudioObjectUnknown,
              let uid = stringProperty(of: deviceID, selector: kAudioDevicePropertyDeviceUID),
              let name = stringProperty(of: deviceID, selector: kAudioObjectPropertyName)
        else { return nil }
        return AudioInputDevice(id: uid, name: name)
    }

    nonisolated private static func stringProperty(of object: AudioObjectID, selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}
#endif
