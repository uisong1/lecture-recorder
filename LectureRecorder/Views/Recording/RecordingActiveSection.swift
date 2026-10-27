import LectureCore
import SwiftUI

/// 녹음 중에 보이는 구역: 입력 크기, 정지·일시정지·북마크, 북마크 메모, 경고 또는 고정 안내.
struct RecordingActiveSection: View {
    let recording: RecordingController

    var body: some View {
        InputLevelBar(level: recording.inputLevel)
            .accessibilityIdentifier("inputLevel")

        Button {
            recording.togglePause()
        } label: {
            Label(recording.isPaused ? "재개" : "일시정지", systemImage: recording.isPaused ? "play.fill" : "pause.fill")
        }
        .buttonStyle(.pillSecondary)
        .keyboardShortcut("p", modifiers: .command)
        .accessibilityIdentifier("pauseButton")

        Button {
            recording.addBookmark()
        } label: {
            Label("북마크 \(recording.bookmarkTimes.count)", systemImage: "bookmark")
        }
        .buttonStyle(.pillSecondary)
        .keyboardShortcut("b", modifiers: .command)
        .help("중요한 구간 표시 (⌘B)")
        .accessibilityIdentifier("bookmarkButton")

        BookmarkNoteField(recording: recording)

        RecordingNoticeLines(notices: RecordingScreenNotices(
            isRecording: true,
            isPaused: recording.isPaused,
            stallResumeNotice: recording.stallResumeNotice,
            storageWarning: recording.storageWarning,
            batteryWarning: recording.batteryWarning,
            inputDeviceWarning: recording.inputDeviceWarning,
            isInputSilent: recording.isInputSilent
        ))
    }
}
