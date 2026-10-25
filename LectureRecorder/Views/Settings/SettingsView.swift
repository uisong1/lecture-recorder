import LectureCore
import SwiftUI

struct SettingsView: View {
    let subjects: SubjectManager
    let schedule: ScheduleManager

    var body: some View {
        TabView {
            SubjectSettingsView(manager: subjects)
                .tabItem { Label("과목", systemImage: "books.vertical") }
            ScheduleSettingsView(subjects: subjects, manager: schedule)
                .tabItem { Label("시간표", systemImage: "calendar") }
        }
        .frame(width: 560, height: 460)
    }
}
