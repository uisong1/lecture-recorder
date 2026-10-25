import LectureCore
import AppKit
import SwiftUI

@main
struct LectureRecorderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var dependencies: AppDependencies
    private let microphonePermission = SystemMicrophonePermission()

    init() {
        let dependencies = AppDependencies()
        _dependencies = State(initialValue: dependencies)
        AppDelegate.quitGuard = QuitGuard(target: dependencies.recording)
    }

    var body: some Scene {
        WindowGroup("수업 녹음") {
            ContentView(dependencies: dependencies)
                .task {
                    // UI 테스트 중에는 권한 창이 화면을 가리지 않도록 묻지 않는다.
                    guard !AppDependencies.isUITesting else { return }
                    _ = await microphonePermission.requestIfNeeded()
                }
        }
        .modelContainer(dependencies.container)

        Settings {
            SettingsView(subjects: dependencies.subjects, schedule: dependencies.schedule)
        }
        .modelContainer(dependencies.container)
    }
}
