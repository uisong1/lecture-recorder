import LectureCore
import SwiftUI

@main
struct LectureRecorderApp: App {
    private let microphonePermission = SystemMicrophonePermission()

    var body: some Scene {
        WindowGroup("수업 녹음") {
            ContentView()
                .task {
                    // UI 테스트 중에는 권한 창이 화면을 가리지 않도록 묻지 않는다.
                    guard !ProcessInfo.processInfo.arguments.contains("-UITesting") else { return }
                    _ = await microphonePermission.requestIfNeeded()
                }
        }
    }
}
