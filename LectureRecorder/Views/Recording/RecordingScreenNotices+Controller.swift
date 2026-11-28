import LectureCore

extension RecordingScreenNotices {
    /// 녹음 중 화면의 경고 목록. 녹음 카드 안의 한 줄 경고와 카드 아래 설명 경고가 같은 순서를 쓴다.
    @MainActor
    static func forRecording(_ recording: RecordingController) -> RecordingScreenNotices {
        RecordingScreenNotices(
            isRecording: true,
            isPaused: recording.isPaused,
            stallResumeNotice: recording.stallResumeNotice,
            storageWarning: recording.storageWarning,
            batteryWarning: recording.batteryWarning,
            inputDeviceWarning: recording.inputDeviceWarning,
            isInputSilent: recording.isInputSilent,
            recoveryJournalFailed: recording.recoveryJournalFailed,
            sleepPreventionFailed: recording.sleepPreventionFailed
        )
    }
}
