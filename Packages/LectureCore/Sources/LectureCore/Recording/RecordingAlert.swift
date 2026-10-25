import Foundation

/// 앱이 뒤에 있어도 알아야 하는 녹음 중 문제. 시스템 알림으로 보내며, 같은 녹음 안에서는 종류마다 한 번만 보낸다.
public enum RecordingAlert: Hashable, CaseIterable, Sendable {
    case savedBeforeSleep
    case savedBeforeQuit
    case inputDeviceChanged
    case storageFull
    case recorderStalled
    case inputSilent

    public var title: String {
        switch self {
        case .savedBeforeSleep, .savedBeforeQuit: "녹음이 여기까지 저장됐습니다"
        case .inputDeviceChanged: "마이크 연결이 바뀌었습니다"
        case .storageFull: "저장 공간이 부족해 녹음을 멈췄습니다"
        case .recorderStalled: "녹음이 멈춘 것 같습니다"
        case .inputSilent: "소리가 거의 들어오지 않습니다"
        }
    }

    public var body: String {
        switch self {
        case .savedBeforeSleep: "맥이 잠자기에 들어가 녹음을 멈췄습니다. 다시 시작하세요."
        case .savedBeforeQuit: "앱이 종료되어 녹음을 멈췄습니다. 다시 시작하세요."
        case .inputDeviceChanged: "녹음 중 마이크가 바뀌었거나 끊겼습니다. 소리가 제대로 들어오는지 확인하세요."
        case .storageFull: "지금까지 녹음은 저장했습니다. 공간을 비운 뒤 다시 녹음하세요."
        case .recorderStalled: "지금까지 녹음은 저장했습니다. 녹음을 다시 시작하세요."
        case .inputSilent: "마이크가 가려졌거나 다른 장치로 바뀌지 않았는지 확인하세요."
        }
    }

    /// 알림 식별자. 종류마다 달라야 앞선 알림을 덮어쓰지 않는다.
    public var identifier: String {
        switch self {
        case .savedBeforeSleep: "recording-alert-sleep"
        case .savedBeforeQuit: "recording-alert-quit"
        case .inputDeviceChanged: "recording-alert-input-device"
        case .storageFull: "recording-alert-storage-full"
        case .recorderStalled: "recording-alert-stalled"
        case .inputSilent: "recording-alert-silent"
        }
    }
}
