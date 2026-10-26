import LectureCore
import SwiftUI

/// 정지 직후 "저장됨" 구역. 주 동작(듣기, 이어서 녹음)과 수정 칸을 나눈다.
struct SavedRecordingSection: View {
    let recording: RecordingController
    let playback: PlaybackController
    let manager: RecordingManager
    let library: RecordingLibrary
    let saved: Recording

    @State private var editor: SavedRecordingEditor

    init(recording: RecordingController, playback: PlaybackController, manager: RecordingManager, library: RecordingLibrary, saved: Recording) {
        self.recording = recording
        self.playback = playback
        self.manager = manager
        self.library = library
        self.saved = saved
        _editor = State(initialValue: SavedRecordingEditor(manager: manager, onChange: { library.reload() }))
    }

    var body: some View {
        VStack(spacing: Design.Spacing.xs) {
            HStack(spacing: Design.Spacing.sm) {
                Text("저장됨: \(saved.title)")
                    .designText(.caption)
                    .accessibilityIdentifier("lastSavedTitle")
                Button(playback.current === saved && playback.isPlaying ? "일시정지" : "듣기") {
                    playback.select(saved)
                    playback.togglePlayPause()
                }
                .buttonStyle(.textLink)
                .accessibilityIdentifier("playLastSaved")
                Button("이어서 녹음") {
                    Task { await recording.continueAfterStop() }
                }
                .buttonStyle(.textLink)
                .help("같은 과목으로 새 파일에 바로 이어서 녹음합니다")
                .accessibilityIdentifier("continueRecording")
            }
            .foregroundStyle(Design.Palette.inkMuted)

            Button(editor.isEditing ? "완료" : "제목·과목·메모 수정") {
                if editor.isEditing {
                    editor.save(saved)
                } else {
                    editor.begin(saved)
                }
            }
            .buttonStyle(.textLink)
            .accessibilityIdentifier("editLastSaved")

            if editor.isEditing {
                HStack(spacing: Design.Spacing.sm) {
                    TextField("제목", text: Bindable(editor).title)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                        .onSubmit { editor.save(saved) }
                        .accessibilityIdentifier("lastSavedTitleField")
                    TextField("수업 메모 (예: 과제 공지)", text: Bindable(editor).memo)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                        .onSubmit { editor.save(saved) }
                        .accessibilityIdentifier("lastSavedMemoField")
                    Menu("과목: \(saved.subject?.name ?? SubjectManager.unclassifiedName)") {
                        ForEach(recording.availableSubjects()) { subject in
                            Button(subject.name) { editor.move(saved, to: subject) }
                        }
                        Button(SubjectManager.unclassifiedName) { editor.move(saved, to: nil) }
                    }
                    .fixedSize()
                    .accessibilityIdentifier("lastSavedSubjectMenu")
                }
            }

            if let message = editor.errorMessage ?? manager.errorMessage ?? playback.errorMessage {
                Text(message)
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.danger)
                    .accessibilityIdentifier("lastSavedError")
            }
        }
    }
}
