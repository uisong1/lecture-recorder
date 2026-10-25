import LectureCore
import SwiftUI

/// 고른 과목의 녹음을 최신순으로 보여주고, 눌러서 재생한다.
struct RecordingListView: View {
    let library: RecordingLibrary
    let playback: PlaybackController

    var body: some View {
        Group {
            if library.recordings.isEmpty {
                ContentUnavailableView("녹음이 없습니다", systemImage: "waveform", description: Text("이 과목으로 녹음한 수업이 여기에 나타납니다."))
                    .accessibilityIdentifier("emptyRecordings")
            } else {
                List(library.recordings) { recording in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(recording.title)
                                .designText(.bodyStrong)
                                .foregroundStyle(Design.Palette.ink)
                                .accessibilityIdentifier("recordingRow")
                            Text("\(recording.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(RecordingController.format(recording.duration))")
                                .designText(.caption)
                                .foregroundStyle(Design.Palette.inkMuted)
                        }
                        Spacer()
                        Button(playback.current === recording && playback.isPlaying ? "일시정지" : "듣기") {
                            playback.select(recording)
                            playback.togglePlayPause()
                        }
                        .buttonStyle(.textLink)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollContentBackground(.hidden)
        .designCanvas()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if playback.current != nil { PlaybackBar(playback: playback) }
        }
        .overlay(alignment: .bottom) {
            if let message = library.errorMessage ?? playback.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .designText(.caption)
                    .foregroundStyle(.red)
                    .padding(8)
            }
        }
    }
}
