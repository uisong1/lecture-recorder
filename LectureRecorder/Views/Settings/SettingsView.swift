import LectureCore
import SwiftUI

struct SettingsView: View {
    let subjects: SubjectManager

    var body: some View {
        TabView {
            SubjectSettingsView(manager: subjects)
                .tabItem { Label("과목", systemImage: "books.vertical") }
        }
        .frame(width: 520, height: 420)
    }
}
