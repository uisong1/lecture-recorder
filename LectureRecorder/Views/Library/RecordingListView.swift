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
                                .font(.headline)
                                .accessibilityIdentifier("recordingRow")
                            Text("\(recording.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(RecordingController.format(recording.duration))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(playback.current === recording && playback.isPlaying ? "일시정지" : "듣기") {
                            playback.select(recording)
                            playback.togglePlayPause()
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if let message = library.errorMessage ?? playback.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .padding(8)
            }
        }
    }
}
