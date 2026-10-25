import Foundation

/// 앱 종료 요청(⌘Q, Dock 종료 등)에 대한 첫 판정.
public enum QuitRequestResult: Equatable, Sendable {
    /// 녹음 중이 아니니 바로 종료한다.
    case quitNow
    /// 녹음 중이다. 사용자에게 저장하고 종료할지 물어야 한다.
    case askUser
}

/// 확인 창에서 사용자가 고른 것.
public enum QuitChoice: Equatable, Sendable {
    case saveAndQuit
    case keepRecording
}

/// 사용자의 선택을 처리한 결과.
public enum QuitOutcome: Equatable, Sendable {
    case quit
    /// 종료하지 않는다. 저장에 실패했다면 그 이유를 담는다.
    case keepRunning(errorMessage: String?)
}

/// 종료 판정에 필요한 녹음 쪽 기능. 테스트에서는 가짜 구현을 쓴다.
@MainActor
public protocol QuitGuardTarget: AnyObject {
    var isRecording: Bool { get }
    /// 지금까지의 녹음을 정상 정지해 저장한다.
    func stopForQuit() throws
}

/// 녹음 중 실수로 ⌘Q를 눌러 수업 녹음이 끊기는 사고를 막는다.
/// 녹음 중이면 종료를 한 번 멈추고 물어본 뒤, 저장하고 종료하거나 녹음을 계속한다.
@MainActor
public final class QuitGuard {
    public static let confirmationTitle = "녹음 중입니다. 저장하고 종료할까요?"
    public static let confirmationDetail = "종료하면 지금까지의 녹음을 저장합니다. 취소하면 녹음이 계속됩니다."

    private let target: any QuitGuardTarget

    public init(target: any QuitGuardTarget) {
        self.target = target
    }

    /// 종료 요청이 왔을 때 바로 종료해도 되는지.
    public func requestQuit() -> QuitRequestResult {
        target.isRecording ? .askUser : .quitNow
    }

    /// 확인 창의 선택을 처리한다. 저장에 실패하면 녹음을 끊지 않도록 종료를 취소한다.
    public func resolve(_ choice: QuitChoice) -> QuitOutcome {
        switch choice {
        case .keepRecording:
            return .keepRunning(errorMessage: nil)
        case .saveAndQuit:
            // 확인 창이 떠 있는 사이 녹음이 이미 끝났다면 저장할 것이 없다.
            guard target.isRecording else { return .quit }
            do {
                try target.stopForQuit()
                return .quit
            } catch {
                #if canImport(os)
                Log.recording.error("종료 전 녹음 저장 실패: \(error.localizedDescription, privacy: .public)")
                #endif
                return .keepRunning(errorMessage: "녹음을 저장하지 못해 종료하지 않았습니다: \(error.localizedDescription)")
            }
        }
    }
}

#if canImport(SwiftData)
extension RecordingController: QuitGuardTarget {
    public func stopForQuit() throws {
        _ = try stop()
    }
}
#endif
