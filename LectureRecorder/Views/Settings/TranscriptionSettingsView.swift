import AppKit
import LectureCore
import SwiftUI

/// 설정 > 전사: 전사 도구 설치, 동시에 전사할 개수, 전원 연결 때만 전사 (시안 06-5).
struct TranscriptionSettingsView: View {
    @Bindable var center: TranscriptionCenter

    var body: some View {
        Form {
            Section("전사 모델") {
                LabeledContent {
                    toolStatus
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Qwen3-ASR 1.7B (8bit)")
                        Text("맥 안에서만 처리 · 한국어")
                            .designText(.caption)
                            .foregroundStyle(Design.Palette.inkMuted)
                    }
                }
                if case .failed(let message) = center.toolStatus {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .designText(.captionStrong)
                        .foregroundStyle(Design.Palette.danger)
                }
                if center.toolStatus == .helperMissing {
                    Label(TranscriptionHelperScript.missingMessage, systemImage: "exclamationmark.triangle")
                        .designText(.captionStrong)
                        .foregroundStyle(Design.Palette.danger)
                }
                LabeledContent("전사 기록") {
                    Button("로그 열기") { openLog() }
                        .buttonStyle(.pillSecondaryCompact)
                }
            }
            Section {
                Picker("동시에 전사할 개수", selection: $center.concurrency) {
                    ForEach(Array(TranscriptionQueue.concurrencyRange), id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("transcriptionConcurrency")
                Toggle("전원에 연결돼 있을 때만 전사", isOn: $center.powerOnly)
                    .accessibilityIdentifier("transcriptionPowerOnly")
                LabeledContent("녹음 중에는 전사 잠시 멈춤") {
                    Text("항상")
                        .foregroundStyle(Design.Palette.inkMuted)
                }
            } header: {
                Text("속도와 배터리")
            } footer: {
                Text("개수를 늘리면 빨리 끝나지만 맥이 뜨거워지고 배터리를 더 써요. 녹음은 항상 전사보다 먼저예요.")
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.inkMuted)
            }
        }
        .formStyle(.grouped)
        .padding(Design.Spacing.lg)
        .task { await center.checkTool() }
    }

    @ViewBuilder
    private var toolStatus: some View {
        switch center.toolStatus {
        case .ready:
            Label("준비됨", systemImage: "checkmark.circle")
                .designText(.caption)
                .foregroundStyle(Design.Palette.inkMuted)
        case .checking:
            ProgressView().controlSize(.small)
        case .installing:
            HStack(spacing: Design.Spacing.xs) {
                ProgressView().controlSize(.small)
                Text("설치 중 (몇 분 걸려요)")
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.inkMuted)
            }
        case .notInstalled, .failed:
            Button("전사 도구 설치") { Task { await center.installTool() } }
                .buttonStyle(.pillCompact)
                .accessibilityIdentifier("settingsInstallTranscription")
        case .helperMissing:
            Button("다시 확인") { Task { await center.checkTool() } }
                .buttonStyle(.pillSecondaryCompact)
        }
    }

    private func openLog() {
        // 샌드박스 앱이라 로그 파일 위치는 실제 홈 폴더 기준으로 만든다.
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let realHome = home.components(separatedBy: "/Library/Containers/").first ?? home
        let url = URL(filePath: realHome).appending(path: "Library/Logs/LectureRecorder-transcribe.log")
        if !NSWorkspace.shared.open(url) {
            Log.app.error("전사 로그를 열지 못함: \(url.path, privacy: .public)")
        }
    }
}
