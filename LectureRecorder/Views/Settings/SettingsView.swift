import LectureCore
import SwiftUI

struct SettingsView: View {
    let subjects: SubjectManager
    let schedule: ScheduleManager
    let reminders: ClassReminderController
    let rescan: RecordingRescanModel
    let recording: RecordingController

    var body: some View {
        TabView {
            SubjectSettingsView(manager: subjects)
                .tabItem { Label("과목", systemImage: "books.vertical") }
            ScheduleSettingsView(subjects: subjects, manager: schedule)
                .tabItem { Label("시간표", systemImage: "calendar") }
            NotificationSettingsView(reminders: reminders)
                .tabItem { Label("알림", systemImage: "bell") }
            RecordingFilesSettingsView(model: rescan, isRecording: recording.isRecording)
                .tabItem { Label("녹음 파일", systemImage: "folder") }
        }
        .frame(width: 560, height: 460)
    }
}
