import LectureCore
import SwiftUI

/// 앱 전반 설정 탭: 로그인 시 자동 실행, 재생 건너뛰기 길이.
struct GeneralSettingsView: View {
    let launchAtLogin: LaunchAtLoginModel
    @Bindable var playback: PlaybackController

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
            Section {
                Picker("앞뒤 건너뛰기", selection: $playback.skipInterval) {
                    ForEach(SkipInterval.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .accessibilityIdentifier("skipIntervalPicker")
                Text("재생 막대의 ←/→ 버튼과 이어폰·키보드의 건너뛰기 키가 이 길이만큼 움직입니다.")
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.inkMuted)
            }
        }
        .formStyle(.grouped)
        .padding(Design.Spacing.lg)
        .onAppear { launchAtLogin.refresh() }
    }
}
