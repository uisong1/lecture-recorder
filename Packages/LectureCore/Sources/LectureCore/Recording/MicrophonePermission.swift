/// 마이크 권한 상태.
public enum MicrophonePermissionStatus: Sendable, Equatable {
    /// 아직 묻지 않음.
    case notDetermined
    /// 허용됨.
    case granted
    /// 거부됨 또는 제한됨. 시스템 설정에서 바꿔야 한다.
    case denied
}

/// 마이크 권한을 조회·요청한다. 테스트에서는 가짜 구현을 쓴다.
public protocol MicrophonePermissionProviding: Sendable {
    func currentStatus() -> MicrophonePermissionStatus
    /// 권한을 요청하고 결과 상태를 돌려준다.
    func request() async -> MicrophonePermissionStatus
}

extension MicrophonePermissionProviding {
    /// 아직 묻지 않았을 때만 요청한다. 이미 정해졌으면 그 상태를 그대로 돌려준다.
    public func requestIfNeeded() async -> MicrophonePermissionStatus {
        let status = currentStatus()
        guard status == .notDetermined else { return status }
        return await request()
    }
}

#if canImport(AVFoundation)
import AVFoundation

/// AVFoundation으로 마이크 권한을 다루는 구현.
public struct SystemMicrophonePermission: MicrophonePermissionProviding {
    public init() {}

    public func currentStatus() -> MicrophonePermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined: .notDetermined
        case .authorized: .granted
        case .denied, .restricted: .denied
        @unknown default: .denied
        }
    }

    public func request() async -> MicrophonePermissionStatus {
        await AVCaptureDevice.requestAccess(for: .audio) ? .granted : .denied
    }
}
#endif
