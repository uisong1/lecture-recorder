import LectureCore
import SwiftUI

struct SettingsView: View {
    let subjects: SubjectManager
    let schedule: ScheduleManager
    let reminders: ClassReminderController
    let rescan: RecordingRescanModel
    let recording: RecordingController
    let launchAtLogin: LaunchAtLoginModel
    let storeBackup: StoreBackup?

    var body: some View {
        TabView {
            GeneralSettingsView(launchAtLogin: launchAtLogin)
                .tabItem { Label("일반", systemImage: "gearshape") }
            SubjectSettingsView(manager: subjects)
                .tabItem { Label("과목", systemImage: "books.vertical") }
            ScheduleSettingsView(subjects: subjects, manager: schedule)
                .tabItem { Label("시간표", systemImage: "calendar") }
            NotificationSettingsView(reminders: reminders)
                .tabItem { Label("알림", systemImage: "bell") }
            RecordingFilesSettingsView(model: rescan, isRecording: recording.isRecording, storeBackup: storeBackup)
                .tabItem { Label("녹음 파일", systemImage: "folder") }
        }
        .frame(width: 560, height: 560)
    }
}
