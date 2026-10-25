import Foundation

/// 녹음 중 남은 저장 공간을 어떻게 다룰지 판정한다. 값만 보고 정하는 순수한 로직이라 테스트하기 쉽다.
/// 정지·저장과 화면 경고는 부르는 쪽(`RecordingController`)이 한다.
public enum StorageSpaceStatus: Equatable, Sendable {
    /// 충분하다.
    case enough
    /// 경고할 만큼 부족하다. 지금 속도로 더 녹음할 수 있는 시간(분).
    case low(minutesLeft: Int)
    /// 바닥나기 전에 자동으로 정지·저장해야 한다.
    case critical

    /// 남은 공간이 이보다 적으면 경고한다 (1시간 분량).
    public static let warningBytes = RecordingFormat.workingBytes(for: 3_600)
    /// 남은 공간이 이보다 적으면 바닥나기 전에 자동으로 정지·저장한다 (10분 분량).
    public static let criticalBytes = RecordingFormat.workingBytes(for: 600)

    public static func assess(freeBytes: Int64) -> StorageSpaceStatus {
        if freeBytes < criticalBytes { return .critical }
        if freeBytes < warningBytes {
            return .low(minutesLeft: Int(freeBytes / RecordingFormat.workingBytesPerSecond / 60))
        }
        return .enough
    }

    /// 녹음 화면에 보일 경고. 경고할 일이 없으면 nil.
    public var warningMessage: String? {
        guard case .low(let minutes) = self else { return nil }
        return "저장 공간이 부족합니다. 약 \(minutes)분 더 녹음할 수 있어요. 공간을 비워 주세요."
    }
}
