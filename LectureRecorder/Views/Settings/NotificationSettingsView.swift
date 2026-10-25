import LectureCore
import SwiftUI

/// 수업 시작 알림을 켜고 끄는 설정 탭.
struct NotificationSettingsView: View {
    let reminders: ClassReminderController

    var body: some View {
        Form {
            Section {
                Toggle(
                    "수업 시작 2분 전에 알림",
                    isOn: Binding(
                        get: { reminders.isEnabled },
                        set: { enabled in Task { await reminders.setEnabled(enabled) } }
                    )
                )
                .accessibilityIdentifier("classReminderToggle")
                Text("알림을 누르면 앱이 열립니다. 녹음은 직접 시작해야 하며, 자동으로 녹음하지 않습니다.")
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.inkMuted)
                if let message = reminders.message {
                    Label(message, systemImage: "bell.slash")
                        .designText(.caption)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("classReminderMessage")
                }
            }
        }
        .formStyle(.grouped)
        .padding(Design.Spacing.lg)
    }
}
