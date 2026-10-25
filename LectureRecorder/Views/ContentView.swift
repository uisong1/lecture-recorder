import SwiftUI

struct ContentView: View {
    let startupError: String?

    var body: some View {
        VStack(spacing: 12) {
            if let startupError {
                Label(startupError, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            Text("수업 녹음")
                .accessibilityIdentifier("mainWindowContent")
            SettingsLink {
                Label("과목과 시간표 설정", systemImage: "gearshape")
            }
            .accessibilityIdentifier("openSettings")
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}

#Preview {
    ContentView(startupError: nil)
}
