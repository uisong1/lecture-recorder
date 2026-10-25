import Foundation

/// 마이크 없이 녹음하는 척하는 녹음기. UI 테스트와 미리보기에서 쓴다.
/// 파일은 만들지 않고, 경과 시간은 주어진 시계로 계산한다.
@MainActor
public final class SimulatedAudioRecorder: AudioRecording {
    private let now: @MainActor () -> Date
    private var startedAt: Date?
    private var pausedAt: Date?
    /// 일시정지로 빠진 시간의 합.
    private var pausedTotal: TimeInterval = 0

    public init(now: @escaping @MainActor () -> Date = { Date() }) {
        self.now = now
    }

    public var isRecording: Bool { startedAt != nil }

    public var isPaused: Bool { pausedAt != nil }

    public var currentTime: TimeInterval {
        guard let startedAt else { return 0 }
        return (pausedAt ?? now()).timeIntervalSince(startedAt) - pausedTotal
    }

    /// 소리가 들어오는 것처럼 일정한 크기를 돌려준다 (UI 테스트에서 무음 경고가 뜨지 않도록).
    public var inputLevel: Float { isRecording && !isPaused ? 0.3 : 0 }

    public func start(to url: URL) throws {
        startedAt = now()
        pausedAt = nil
        pausedTotal = 0
    }

    public func pause() {
        guard startedAt != nil, pausedAt == nil else { return }
        pausedAt = now()
    }

    public func resume() throws {
        guard let pausedAt else { return }
        pausedTotal += now().timeIntervalSince(pausedAt)
        self.pausedAt = nil
    }

    public func stop() -> TimeInterval {
        let duration = currentTime
        startedAt = nil
        pausedAt = nil
        pausedTotal = 0
        return duration
    }
}

/// 항상 허용된 마이크 권한. UI 테스트와 미리보기에서 쓴다.
public struct GrantedMicrophonePermission: MicrophonePermissionProviding {
    public init() {}
    public func currentStatus() -> MicrophonePermissionStatus { .granted }
    public func request() async -> MicrophonePermissionStatus { .granted }
}
