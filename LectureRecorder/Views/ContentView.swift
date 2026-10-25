import LectureCore
import SwiftUI

struct ContentView: View {
    var body: some View {
        Text("수업 녹음")
            .frame(minWidth: 600, minHeight: 400)
            .accessibilityIdentifier("mainWindowContent")
            .help(LectureCore.appName)
    }
}

#Preview {
    ContentView()
}
