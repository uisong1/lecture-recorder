import Foundation

/// 녹음 화면에 보일 경고와 고정 안내를 고른다. 경고가 있으면 고정 안내는 숨겨 경고가 가장 눈에 띄게 한다.
public struct RecordingScreenNotices: Equatable, Sendable {
    public enum Kind: Hashable, Sendable {
        case stallResume, storage, battery, inputDevice, silence
    }

    public struct Warning: Equatable, Sendable {
        public var kind: Kind
        public var message: String

        public init(kind: Kind, message: String) {
            self.kind = kind
            self.message = message
        }
    }

    /// 녹음 중 늘 보이던 안내 두 줄(덮개, 창 닫기)을 합친 한 줄.
    public static let standingText = "덮개를 닫으면 멈춥니다 · 창을 닫아도 녹음은 계속됩니다"
    public static let silenceMessage = "소리가 거의 들어오지 않습니다"

    /// 위에서부터 중요한 순서. 비어 있으면 경고가 없다.
    public let warnings: [Warning]
    /// 경고가 없고 녹음 중일 때만 있다.
    public let standingNotice: String?

    public init(
        isRecording: Bool,
        isPaused: Bool,
        stallResumeNotice: String?,
        storageWarning: String?,
        batteryWarning: String?,
        inputDeviceWarning: String?,
        isInputSilent: Bool
    ) {
        var result: [Warning] = []
        if isRecording, let message = stallResumeNotice { result.append(Warning(kind: .stallResume, message: message)) }
        if isRecording, let message = storageWarning { result.append(Warning(kind: .storage, message: message)) }
        if isRecording, let message = batteryWarning { result.append(Warning(kind: .battery, message: message)) }
        if let message = inputDeviceWarning { result.append(Warning(kind: .inputDevice, message: message)) }
        // 일시정지 중에는 소리가 안 들어오는 것이 당연하다.
        if isRecording, !isPaused, isInputSilent { result.append(Warning(kind: .silence, message: Self.silenceMessage)) }
        warnings = result
        standingNotice = isRecording && result.isEmpty ? Self.standingText : nil
    }
}
