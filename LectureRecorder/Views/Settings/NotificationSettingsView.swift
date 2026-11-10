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
            Section {
                Toggle(
                    "수업이 시작됐는데 녹음 전이면 노치에 불빛",
                    isOn: Binding(get: { reminders.isNotchAlertEnabled }, set: { reminders.setNotchAlertEnabled($0) })
                )
                .accessibilityIdentifier("notchAlertToggle")
                Text("수업 시작 시각에 녹음 전이면 화면 맨 위 가운데에 파란 불빛이 10분 동안 켜집니다(녹음을 시작하면 꺼집니다). 누르면 그 과목이 골라진 녹음 창이 열리고, 녹음은 \"녹음 시작\"을 눌러야만 시작됩니다. 소리는 나지 않습니다.")
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.inkMuted)
            }
        }
        .formStyle(.grouped)
        .padding(Design.Spacing.lg)
    }
}
