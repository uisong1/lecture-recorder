import LectureCore
import AppKit
import SwiftUI

/// 녹음 파일을 다시 읽어 목록에 되살리는 설정 탭.
struct RecordingFilesSettingsView: View {
    let model: RecordingRescanModel
    let isRecording: Bool
    let storeBackup: StoreBackup?
    let storage: RecordingStorage

    @AppStorage(LMSImportModel.keepVideoDefaultsKey) private var keepLMSVideo = false
    @State private var lastBackup: Date?
    @State private var folder: RecordingsFolderInfo?
    @State private var folderMessage: String?

    private var lastBackupText: String {
        guard let lastBackup else { return "마지막 백업: 아직 없음" }
        return "마지막 백업: \(lastBackup.formatted(date: .long, time: .omitted))"
    }

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
            Section("녹음 폴더") {
                if let folder {
                    Text(folder.displayPath())
                        .designText(.body)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("recordingsFolderPath")
                }
                Text(RecordingsFolderInfo.archiveGuide)
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.inkMuted)
                    .accessibilityIdentifier("recordingsFolderGuide")
                Button("녹음 폴더 열기") { openRecordingsFolder() }
                    .buttonStyle(.pill)
                    .accessibilityIdentifier("openRecordingsFolderButton")
                if let folderMessage {
                    Text(folderMessage)
                        .designText(.caption)
                        .foregroundStyle(Design.Palette.danger)
                        .accessibilityIdentifier("recordingsFolderMessage")
                }
            }
            Section("LMS 영상") {
                Toggle("가져올 때 영상(mp4)도 보관", isOn: $keepLMSVideo)
                    .accessibilityIdentifier("keepLMSVideo")
                Text("끄면 소리(m4a)만 저장합니다. 켜면 소리 파일 옆에 영상 파일이 함께 저장되어 용량이 크게 늘어납니다. LMS 영상은 개인 복습용이라 공유·업로드·다른 곳에 저장에서 빠집니다.")
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.inkMuted)
            }
            if let storeBackup {
                Section("목록 백업") {
                    Text("과목·시간표·녹음 목록은 앱을 켤 때 하루에 한 번 백업됩니다. 녹음 파일(.m4a)은 백업 대상이 아니며, 목록이 사라져도 위의 \"녹음 폴더 다시 읽기\"로 되살립니다.")
                        .designText(.caption)
                        .foregroundStyle(Design.Palette.inkMuted)
                    Text(lastBackupText)
                        .designText(.body)
                        .accessibilityIdentifier("lastBackupText")
                    HStack {
                        Button("저장소 폴더 열기") { NSWorkspace.shared.open(storeBackup.storeFolderURL) }
                            .buttonStyle(.pillSecondary)
                            .accessibilityIdentifier("openStoreFolderButton")
                        Button("백업 폴더 열기") { NSWorkspace.shared.open(storeBackup.folderURL) }
                            .buttonStyle(.pill)
                            .disabled(lastBackup == nil)
                            .accessibilityIdentifier("openBackupFolderButton")
                    }
                    VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                        Text("목록이 망가졌을 때 되살리는 순서")
                            .designText(.caption)
                        Text("1. 앱을 완전히 종료합니다(⌘Q).\n2. \"저장소 폴더 열기\"로 연 폴더의 default.store 파일들을 다른 이름의 폴더로 옮겨 보관합니다. 지우지 마세요.\n3. 백업 폴더에서 원하는 날짜 폴더의 파일을 모두 저장소 폴더로 복사합니다.\n4. 앱을 다시 켭니다.")
                            .designText(.caption)
                            .foregroundStyle(Design.Palette.inkMuted)
                        Text("자동으로 되살리지는 않습니다. 잘못 쓰면 가장 최근 기록을 덮어쓰기 때문입니다.")
                            .designText(.caption)
                            .foregroundStyle(Design.Palette.inkMuted)
                    }
                }
            }
        }
        .task {
            lastBackup = storeBackup?.lastBackupDate()
            folder = storage.folderInfo()
        }
        .formStyle(.grouped)
        .padding(Design.Spacing.lg)
    }

    private func openRecordingsFolder() {
        let info = storage.folderInfo()
        folder = info
        guard info.isAvailable else {
            Log.storage.error("녹음 폴더를 열 수 없음: \(info.url.path, privacy: .public)")
            folderMessage = RecordingsFolderInfo.missingNotice
            return
        }
        folderMessage = NSWorkspace.shared.open(info.url) ? nil : "Finder에서 녹음 폴더를 열지 못했습니다."
    }
}
