import LectureCore
import SwiftUI

/// 녹음 파일을 다시 읽어 목록에 되살리는 설정 탭.
struct RecordingFilesSettingsView: View {
    let model: RecordingRescanModel
    let isRecording: Bool

    var body: some View {
        Form {
            Section {
                Text("녹음 폴더에 있는데 목록에 없는 파일을 찾아 목록에 되살립니다. 휴지통에서 되돌린 파일이나 앱을 다시 설치한 뒤에 쓸 수 있습니다. 파일은 옮기거나 지우지 않고, 비어 있는 폴더만 정리합니다.")
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.inkMuted)
                HStack {
                    Button("녹음 폴더 다시 읽기") { Task { await model.run() } }
                        .buttonStyle(.pill)
                        .disabled(model.isRunning || isRecording)
                        .accessibilityIdentifier("rescanButton")
                    if model.isRunning { ProgressView().controlSize(.small) }
                }
                if isRecording {
                    Text("녹음 중에는 다시 읽을 수 없습니다.")
                        .designText(.caption)
                        .foregroundStyle(Design.Palette.inkMuted)
                }
                if let message = model.message {
                    Text(message)
                        .designText(.caption)
                        .foregroundStyle(model.isError ? Design.Palette.danger : Design.Palette.inkMuted)
                        .accessibilityIdentifier("rescanMessage")
                }
            }
        }
        .formStyle(.grouped)
        .padding(Design.Spacing.lg)
    }
}
