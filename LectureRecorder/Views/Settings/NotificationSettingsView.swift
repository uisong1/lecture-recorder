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
                Text("알림의 \"녹음 시작\" 버튼을 누르면 그 과목으로 녹음을 시작합니다. 알림 본문을 누르면 앱만 열리고, 버튼을 누르지 않으면 녹음하지 않습니다.")
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.inkMuted)
                if let message = reminders.message {
                    Label(message, systemImage: "bell.slash")
                        .designText(.caption)
                        .foregroundStyle(Design.Palette.danger)
                        .accessibilityIdentifier("classReminderMessage")
                }
            }
        }
        .formStyle(.grouped)
        .padding(Design.Spacing.lg)
    }
}
