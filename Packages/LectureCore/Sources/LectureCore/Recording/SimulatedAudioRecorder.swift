import Foundation

/// 마이크 없이 녹음하는 척하는 녹음기. UI 테스트와 미리보기에서 쓴다.
/// 파일은 만들지 않고, 경과 시간은 주어진 시계로 계산한다.
@MainActor
public final class SimulatedAudioRecorder: AudioRecording {
    private let now: @MainActor () -> Date
    private var startedAt: Date?

    public init(now: @escaping @MainActor () -> Date = { Date() }) {
        self.now = now
    }

    public var isRecording: Bool { startedAt != nil }

    public var currentTime: TimeInterval {
        startedAt.map { now().timeIntervalSince($0) } ?? 0
    }

    public func start(to url: URL) throws {
        startedAt = now()
    }

    public func stop() -> TimeInterval {
        let duration = currentTime
        startedAt = nil
        return duration
    }
}

/// 항상 허용된 마이크 권한. UI 테스트와 미리보기에서 쓴다.
public struct GrantedMicrophonePermission: MicrophonePermissionProviding {
    public init() {}
    public func currentStatus() -> MicrophonePermissionStatus { .granted }
    public func request() async -> MicrophonePermissionStatus { .granted }
}
