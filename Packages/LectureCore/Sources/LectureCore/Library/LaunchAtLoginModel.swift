#if canImport(SwiftData)
import Foundation
import Observation

/// 로그인할 때 앱을 자동으로 여는 시스템 설정. 테스트에서는 가짜 구현을 쓴다.
@MainActor
public protocol LoginItemControlling: AnyObject {
    /// 지금 시스템에 등록돼 있는지.
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
}

public enum LoginItemStatus: Equatable, Sendable {
    case enabled
    case notRegistered
    /// 등록은 됐지만 사용자가 시스템 설정 > 일반 > 로그인 항목에서 허용해야 켜진다.
    case requiresApproval
    /// 시스템이 이 앱을 로그인 항목으로 찾지 못함 (앱을 /Applications 밖에서 열었을 때 등).
    case notFound
}

/// 로그인 시 앱 자동 실행을 켜고 끈다. 기본은 꺼짐이고, 사용자가 설정에서 켤 때만 등록한다.
/// 자동 실행은 앱을 열어 둘 뿐이며 녹음은 자동으로 시작하지 않는다.
@MainActor
@Observable
public final class LaunchAtLoginModel {
    /// 켜져 있는지 (시스템에 등록되어 있거나 허용만 기다리는 중).
    public private(set) var isEnabled = false
    /// 화면에 보일 안내. 문제가 없으면 nil.
    public private(set) var message: String?

    private let controller: any LoginItemControlling

    public init(controller: any LoginItemControlling) {
        self.controller = controller
        refresh()
    }

    /// 시스템 상태를 다시 읽는다. 사용자가 시스템 설정에서 직접 바꿨을 수 있으므로 설정 화면을 열 때 부른다.
    public func refresh() {
        apply(controller.status)
    }

    public func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try controller.register()
            } else {
                try controller.unregister()
            }
            refresh()
        } catch {
            Log.app.error("로그인 시 자동 실행 \(enabled ? "켜기" : "끄기", privacy: .public) 실패: \(error.localizedDescription, privacy: .public)")
            refresh()
            message = enabled
                ? "로그인 시 자동 실행을 켜지 못했습니다. 앱을 응용 프로그램 폴더로 옮긴 뒤 다시 시도해 주세요."
                : "로그인 시 자동 실행을 끄지 못했습니다. 시스템 설정 > 일반 > 로그인 항목에서 직접 꺼 주세요."
        }
    }

    private func apply(_ status: LoginItemStatus) {
        switch status {
        case .enabled:
            isEnabled = true
            message = nil
        case .notRegistered:
            isEnabled = false
            message = nil
        case .requiresApproval:
            isEnabled = true
            message = "시스템 설정 > 일반 > 로그인 항목에서 LectureRecorder를 허용해야 켜집니다."
        case .notFound:
            isEnabled = false
            message = "이 위치의 앱은 로그인 항목으로 등록할 수 없습니다. 앱을 응용 프로그램 폴더로 옮긴 뒤 다시 시도해 주세요."
        }
    }
}
#endif
