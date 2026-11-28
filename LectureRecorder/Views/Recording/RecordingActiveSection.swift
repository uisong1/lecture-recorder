import LectureCore
import SwiftUI

/// 녹음 중에 보이는 구역: 입력 크기, 일시정지, 경고 또는 고정 안내.
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

        RecordingNoticeLines(notices: .forRecording(recording))
    }
}
