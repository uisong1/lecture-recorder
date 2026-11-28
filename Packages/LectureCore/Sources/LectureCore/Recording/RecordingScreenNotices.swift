import Foundation

/// 녹음 화면에 보일 경고와 고정 안내를 고른다. 경고가 있으면 고정 안내는 숨겨 경고가 가장 눈에 띄게 한다.
public struct RecordingScreenNotices: Equatable, Sendable {
    public enum Kind: Hashable, Sendable {
        case stallResume, recoveryJournal, sleepPrevention, storage, battery, inputDevice, silence
    }

    public struct Warning: Equatable, Sendable {
        public var kind: Kind
        public var message: String
        /// 굵은 첫 줄 아래 회색으로 덧붙이는 설명. 없으면 한 줄만 보인다.
        public var detail: String?

        public init(kind: Kind, message: String, detail: String? = nil) {
            self.kind = kind
            self.message = message
            self.detail = detail
        }
    }

    /// 녹음 중 늘 보이던 안내 두 줄(덮개, 창 닫기)을 합친 한 줄.
    public static let standingText = "덮개를 닫으면 멈춥니다 · 창을 닫아도 녹음은 계속됩니다"
    public static let silenceMessage = "소리가 거의 들어오지 않습니다"
    public static let recoveryJournalMessage = "앱이 꺼지면 이 녹음을 되살리지 못할 수 있어요"
    public static let recoveryJournalDetail = "복구 기록을 쓰지 못했어요. 녹음은 계속돼요. 정지 버튼으로 끝내면 그대로 저장돼요."
    public static let sleepPreventionMessage = "맥이 잠들 수 있어요"
    public static let sleepPreventionDetail = "잠자기 막기를 켜지 못했어요. 덮개를 닫지 말고 전원을 연결해 두세요."

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
        isInputSilent: Bool,
        recoveryJournalFailed: Bool = false,
        sleepPreventionFailed: Bool = false
    ) {
        var result: [Warning] = []
        if isRecording, let message = stallResumeNotice { result.append(Warning(kind: .stallResume, message: message)) }
        if isRecording, recoveryJournalFailed {
            result.append(Warning(kind: .recoveryJournal, message: Self.recoveryJournalMessage, detail: Self.recoveryJournalDetail))
        }
        if isRecording, sleepPreventionFailed {
            result.append(Warning(kind: .sleepPrevention, message: Self.sleepPreventionMessage, detail: Self.sleepPreventionDetail))
        }
        if isRecording, let message = storageWarning { result.append(Warning(kind: .storage, message: message)) }
        if isRecording, let message = batteryWarning { result.append(Warning(kind: .battery, message: message)) }
        if let message = inputDeviceWarning { result.append(Warning(kind: .inputDevice, message: message)) }
        // 일시정지 중에는 소리가 안 들어오는 것이 당연하다.
        if isRecording, !isPaused, isInputSilent { result.append(Warning(kind: .silence, message: Self.silenceMessage)) }
        warnings = result
        standingNotice = isRecording && result.isEmpty ? Self.standingText : nil
    }
}
