import LectureCore
import SwiftUI

/// 앱 전반 설정 탭. 지금은 로그인 시 자동 실행만 있다.
struct GeneralSettingsView: View {
    let launchAtLogin: LaunchAtLoginModel

    var body: some View {
        Form {
            Section {
                Toggle(
                    "로그인할 때 앱 자동 실행",
                    isOn: Binding(get: { launchAtLogin.isEnabled }, set: { launchAtLogin.setEnabled($0) })
                )
                .accessibilityIdentifier("launchAtLoginToggle")
                Text("맥을 켜면 앱이 열려 있어 수업 시작 알림과 메뉴 막대 아이콘을 바로 쓸 수 있습니다. 녹음은 직접 시작해야 하며, 자동으로 녹음하지 않습니다.")
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.inkMuted)
                if let message = launchAtLogin.message {
                    Label(message, systemImage: "exclamationmark.circle")
                        .designText(.caption)
                        .foregroundStyle(Design.Palette.danger)
                        .accessibilityIdentifier("launchAtLoginMessage")
                }
            }
        }
        .formStyle(.grouped)
        .padding(Design.Spacing.lg)
        .onAppear { launchAtLogin.refresh() }
    }
}
