import LectureCore
import SwiftUI

struct ContentView: View {
    let dependencies: AppDependencies

    var body: some View {
        VStack(spacing: 0) {
            if let startupError = dependencies.startupError {
                Label(startupError, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .padding(8)
            }
            if let notice = dependencies.recoveryNotice {
                Label(notice, systemImage: "arrow.counterclockwise")
                    .foregroundStyle(.blue)
                    .padding(8)
                    .accessibilityIdentifier("recoveryNotice")
            }
            NavigationSplitView {
                LibraryView(library: dependencies.library, subjects: dependencies.subjects)
            } detail: {
                VStack(spacing: 0) {
                    RecordingView(recording: dependencies.recording, playback: dependencies.playback)
                    Divider()
                    RecordingListView(library: dependencies.library)
                        .frame(minHeight: 160)
                }
            }
            .onChange(of: dependencies.recording.lastSaved?.persistentModelID) { dependencies.library.reload() }
            .onChange(of: dependencies.subjects.subjects.count) { dependencies.library.reload() }
        }
        .frame(minWidth: 800, minHeight: 600)
        .toolbar {
            SettingsLink {
                Label("과목과 시간표 설정", systemImage: "gearshape")
            }
            .accessibilityIdentifier("openSettings")
        }
    }
}
