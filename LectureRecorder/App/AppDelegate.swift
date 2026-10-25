import AppKit
import LectureCore

/// ⌘Q 같은 종료 요청을 가로채, 녹음 중이면 확인을 받는다.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 앱 시작 때 `LectureRecorderApp`이 채운다.
    @MainActor static var quitGuard: QuitGuard?

    @MainActor
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let quitGuard = Self.quitGuard, quitGuard.requestQuit() == .askUser else { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = QuitGuard.confirmationTitle
        alert.informativeText = QuitGuard.confirmationDetail
        alert.addButton(withTitle: "저장하고 종료")
        alert.addButton(withTitle: "계속 녹음")
        let choice: QuitChoice = alert.runModal() == .alertFirstButtonReturn ? .saveAndQuit : .keepRecording

        switch quitGuard.resolve(choice) {
        case .quit:
            return .terminateNow
        case .keepRunning(let errorMessage):
            if let errorMessage {
                let failure = NSAlert()
                failure.alertStyle = .warning
                failure.messageText = errorMessage
                failure.runModal()
            }
            return .terminateCancel
        }
    }
}
