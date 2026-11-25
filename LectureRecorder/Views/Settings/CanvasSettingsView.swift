import AppKit
import LectureCore
import SwiftUI

/// 설정 > LMS 탭: Canvas 개인 액세스 토큰. 토큰은 Keychain에만 저장하고 값은 다시 보여 주지 않는다.
struct CanvasSettingsView: View {
    @Bindable var model: CanvasTokenModel
    let materials: LectureMaterialsModel
    let storage: RecordingStorage

    var body: some View {
        Form {
            Section {
                if model.hasToken {
                    Label("토큰이 저장되어 있습니다", systemImage: "checkmark.circle")
                        .designText(.caption)
                        .foregroundStyle(Design.Palette.primary)
                        .accessibilityIdentifier("canvasTokenSaved")
                    Button("토큰 지우기") { model.delete() }
                        .buttonStyle(.pillSecondary)
                        .accessibilityIdentifier("canvasTokenDelete")
                } else {
                    Text("토큰을 먼저 저장해야 강의자료와 영상을 가져올 수 있습니다.")
                        .designText(.caption)
                        .foregroundStyle(Design.Palette.inkMuted)
                        .accessibilityIdentifier("canvasTokenHint")
                    SecureField("토큰을 붙여 넣으세요", text: $model.input)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Canvas 액세스 토큰")
                        .accessibilityIdentifier("canvasTokenField")
                    Button("저장") { model.save() }
                        .buttonStyle(.pill)
                        .disabled(!model.canSave)
                        .accessibilityIdentifier("canvasTokenSave")
                }
                if let message = model.message {
                    Label(message, systemImage: "exclamationmark.circle")
                        .designText(.caption)
                        .foregroundStyle(Design.Palette.danger)
                        .accessibilityIdentifier("canvasTokenMessage")
                }
            }
            Section("강의자료") {
                Text("수강 중인 과목의 PDF 강의자료를 받아, 이름이 같은 앱 과목의 녹음 폴더 안 \"강의자료\" 폴더에 저장합니다. 이미 받은 파일은 건너뜁니다.")
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.inkMuted)
                HStack {
                    Button("강의자료 PDF 가져오기") { Task { await materials.start() } }
                        .buttonStyle(.pill)
                        .disabled(!model.hasToken || materials.isBusy)
                        .accessibilityIdentifier("materialsStart")
                    Button("녹음 폴더 열기") { NSWorkspace.shared.open(storage.root) }
                        .buttonStyle(.pillSecondary)
                        .accessibilityIdentifier("materialsOpenFolder")
                }
                switch materials.status {
                case .idle:
                    EmptyView()
                case .working(let message):
                    HStack(spacing: Design.Spacing.xs) {
                        ProgressView().controlSize(.small)
                        Text(message).designText(.caption).foregroundStyle(Design.Palette.inkMuted)
                    }
                    .accessibilityIdentifier("materialsWorking")
                case .done(let headline, let details):
                    Text(headline).designText(.caption).foregroundStyle(Design.Palette.ink)
                        .accessibilityIdentifier("materialsDone")
                    if !details.isEmpty {
                        DisclosureGroup("자세히 보기") {
                            Text(details)
                                .designText(.caption)
                                .foregroundStyle(Design.Palette.inkMuted)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("materialsDetails")
                        }
                        .designText(.caption)
                    }
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.circle")
                        .designText(.caption)
                        .foregroundStyle(Design.Palette.danger)
                        .accessibilityIdentifier("materialsFailed")
                }
            }
            Section {
                Text("녹음이 없는 수업일을 LMS 강의 영상의 소리로 채우거나 PDF 강의자료를 받을 때만 씁니다. canvas.ssu.ac.kr > 계정 > 설정 > \"새 액세스 토큰\"에서 만료일을 정해 만드세요. 토큰은 이 맥의 Keychain에만 저장되고 파일·저장소·로그에 남지 않으며, 다른 곳으로 보내지 않습니다. 더 이상 쓰지 않으면 지우고, Canvas에서도 토큰을 삭제하세요.")
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.inkMuted)
            }
        }
        .formStyle(.grouped)
        .padding(Design.Spacing.lg)
        .onAppear { model.refresh() }
    }
}
