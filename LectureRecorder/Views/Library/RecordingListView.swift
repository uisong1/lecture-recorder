import LectureCore
import SwiftUI

/// 고른 과목의 녹음을 최신순으로 보여주고, 눌러서 재생한다.
struct RecordingListView: View {
    let library: RecordingLibrary
    let playback: PlaybackController
    let manager: RecordingManager

    @State private var renaming: Recording?
    @State private var renameText = ""
    @State private var deleting: Recording?

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
                    .contextMenu {
                        Button("이름 변경…") {
                            renameText = recording.title
                            renaming = recording
                        }
                        Menu("과목 이동") {
                            ForEach(library.subjects) { subject in
                                Button(subject.name) { perform { try manager.move(recording, to: subject) } }
                            }
                            Button(RecordingStorage.unclassifiedFolder) { perform { try manager.move(recording, to: nil) } }
                        }
                        Divider()
                        Button("삭제…", role: .destructive) { deleting = recording }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollContentBackground(.hidden)
        .designCanvas()
        .alert("이름 변경", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("제목", text: $renameText)
            Button("취소", role: .cancel) {}
            Button("변경") {
                if let recording = renaming { perform { try manager.rename(recording, to: renameText) } }
            }
        }
        .confirmationDialog(
            "‘\(deleting?.title ?? "")’을(를) 삭제할까요?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("삭제", role: .destructive) {
                if let recording = deleting {
                    if playback.current === recording { playback.select(nil) }
                    perform { try manager.delete(recording) }
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("녹음 파일이 함께 지워지고 되돌릴 수 없습니다.")
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if playback.current != nil { PlaybackBar(playback: playback) }
        }
        .overlay(alignment: .bottom) {
            if let message = manager.errorMessage ?? library.errorMessage ?? playback.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .designText(.caption)
                    .foregroundStyle(.red)
                    .padding(8)
            }
        }
    }

    /// 동작을 실행하고 목록을 다시 읽는다. 오류 문구는 `manager.errorMessage`에 남는다.
    private func perform(_ action: () throws -> Void) {
        try? action()
        library.reload()
    }
}
