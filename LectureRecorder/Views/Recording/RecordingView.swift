import LectureCore
import SwiftUI

/// 녹음 버튼 하나로 시작·정지하는 화면.
struct RecordingView: View {
    let recording: RecordingController
    let playback: PlaybackController

    var body: some View {
        VStack(spacing: 20) {
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                VStack(spacing: 6) {
                    Text(recording.isRecording ? recording.currentSubjectName : "녹음 대기")
                        .font(.title2.bold())
                        .accessibilityIdentifier("recordingSubject")
                    Text(recording.elapsedText)
                        .font(.system(size: 48, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .accessibilityIdentifier("elapsedTime")
                }
            }

            Button {
                Task { await recording.toggle() }
            } label: {
                Image(systemName: recording.isRecording ? "stop.circle.fill" : "record.circle")
                    .font(.system(size: 64))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("r", modifiers: .command)
            .help(recording.isRecording ? "녹음 정지 (⌘R)" : "녹음 시작 (⌘R)")
            .accessibilityLabel(recording.isRecording ? "녹음 정지" : "녹음 시작")
            .accessibilityIdentifier("recordButton")

            if let message = recording.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("recordingError")
            }

            if let saved = recording.lastSaved, !recording.isRecording {
                HStack {
                    Text("저장됨: \(saved.title)")
                        .accessibilityIdentifier("lastSavedTitle")
                    Button(playback.current === saved && playback.isPlaying ? "일시정지" : "듣기") {
                        playback.select(saved)
                        playback.togglePlayPause()
                    }
                    .accessibilityIdentifier("playLastSaved")
                }
                .foregroundStyle(.secondary)
                if let message = playback.errorMessage {
                    Text(message).foregroundStyle(.red)
                }
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
