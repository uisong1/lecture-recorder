import LectureCore
import SwiftUI

/// 설정 > LMS 탭: Canvas 개인 액세스 토큰. 토큰은 Keychain에만 저장하고 값은 다시 보여 주지 않는다.
struct CanvasSettingsView: View {
    @Bindable var model: CanvasTokenModel

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
                    SecureField("Canvas 액세스 토큰", text: $model.input)
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
            Section {
                Text("녹음이 없는 수업일을 LMS 강의 영상의 소리로 채울 때만 씁니다. canvas.ssu.ac.kr > 계정 > 설정 > \"새 액세스 토큰\"에서 만료일을 정해 만드세요. 토큰은 이 맥의 Keychain에만 저장되고 파일·저장소·로그에 남지 않으며, 다른 곳으로 보내지 않습니다. 더 이상 쓰지 않으면 지우고, Canvas에서도 토큰을 삭제하세요.")
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.inkMuted)
            }
        }
        .formStyle(.grouped)
        .padding(Design.Spacing.lg)
        .onAppear { model.refresh() }
    }
}
