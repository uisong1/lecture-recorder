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
            RecordingView(recording: dependencies.recording, playback: dependencies.playback)
        }
        .frame(minWidth: 600, minHeight: 400)
        .toolbar {
            SettingsLink {
                Label("과목과 시간표 설정", systemImage: "gearshape")
            }
            .accessibilityIdentifier("openSettings")
        }
    }
}
