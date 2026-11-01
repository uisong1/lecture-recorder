#if canImport(SwiftData)
import Foundation
import Observation

/// 최신 릴리스를 알아본다. 테스트에서는 가짜 구현을 쓴다.
public protocol AppUpdateChecking: Sendable {
    /// 가장 새 릴리스. 하나도 없으면 nil.
    func latestRelease() async throws -> AppRelease?
}

/// 새 버전을 받아 설치한다. 실제 구현은 앱 쪽에서 업데이트 도우미 스크립트를 부른다.
@MainActor
public protocol AppUpdateInstalling: AnyObject {
    /// 새 앱을 받아 검증해 둔다. 아직 앱을 바꾸지 않는다.
    func download(_ release: AppRelease) async throws
    /// 받아 둔 앱으로 바꾸고 다시 연다. 이 앱이 종료된 뒤 도우미가 마저 한다.
    func installAfterQuit(_ release: AppRelease) async throws
}

public enum AppUpdateError: LocalizedError, Equatable, Sendable {
    /// 업데이트 도우미가 설치돼 있지 않음 (install.sh를 한 번도 새로 돌리지 않았을 때).
    case helperMissing
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .helperMissing:
            "업데이트 도우미가 아직 없습니다. 저장소 폴더에서 ./scripts/install.sh를 한 번 실행하면 이후부터 앱 안에서 업데이트할 수 있습니다."
        case .failed(let message):
            message
        }
    }
}

public enum AppUpdateState: Equatable, Sendable {
    case idle
    case checking
    case upToDate
    case available(AppRelease)
    case downloading(AppRelease)
    /// 받기를 마치고 앱을 종료해 바꾸는 중.
    case installing(AppRelease)
    case failed(String)
}

/// "새 버전 있음 → 업데이트" 흐름. 녹음 중에는 설치하지 않는다.
@MainActor
@Observable
public final class AppUpdateModel {
    public static let recordingMessage = "녹음 중에는 업데이트할 수 없습니다. 녹음을 마친 뒤 다시 시도해 주세요."
    /// 자동 확인 간격 (앱을 켜 둔 동안 하루에 한 번).
    public static let automaticInterval: TimeInterval = 24 * 60 * 60

    public private(set) var state: AppUpdateState = .idle
    public let currentBuild: Int

    private let checker: any AppUpdateChecking
    private let installer: any AppUpdateInstalling
    private let isRecording: () -> Bool
    private let quit: () -> Void
    private var lastChecked: Date?

    /// - Parameters:
    ///   - currentBuild: 지금 실행 중인 앱의 빌드 번호 (CFBundleVersion).
    ///   - isRecording: 녹음 중인지.
    ///   - quit: 앱을 종료하라고 요청한다. 녹음 종료 확인 같은 정상 종료 절차를 그대로 거친다.
    public init(
        currentBuild: Int,
        checker: any AppUpdateChecking,
        installer: any AppUpdateInstalling,
        isRecording: @escaping () -> Bool,
        quit: @escaping () -> Void
    ) {
        self.currentBuild = currentBuild
        self.checker = checker
        self.installer = installer
        self.isRecording = isRecording
        self.quit = quit
    }

    public var availableRelease: AppRelease? {
        if case .available(let release) = state { return release }
        return nil
    }

    public var isBusy: Bool {
        switch state {
        case .checking, .downloading, .installing: true
        default: false
        }
    }

    /// 지금 업데이트를 눌러도 되는지.
    public var canInstall: Bool { availableRelease != nil && !isRecording() }

    /// 마지막 확인으로부터 하루가 지났으면 조용히 확인한다. 실패해도 화면에 오류를 띄우지 않는다.
    public func checkAutomaticallyIfDue(now: Date) async {
        if let lastChecked, now.timeIntervalSince(lastChecked) < Self.automaticInterval { return }
        guard !isBusy else { return }
        await check(now: now, silent: true)
    }

    public func check(now: Date, silent: Bool = false) async {
        guard !isBusy else { return }
        let previous = state
        state = .checking
        lastChecked = now
        do {
            if let release = try await checker.latestRelease(), release.build > currentBuild {
                state = .available(release)
            } else {
                state = .upToDate
            }
        } catch {
            Log.app.error("업데이트 확인 실패: \(error.localizedDescription, privacy: .public)")
            state = silent ? previous : .failed("새 버전을 확인하지 못했습니다. 인터넷 연결을 확인한 뒤 다시 시도해 주세요.")
        }
    }

    /// 받고, 녹음 중이 아닌지 한 번 더 확인한 뒤, 앱을 종료해 바꾼다.
    public func install() async {
        guard case .available(let release) = state else { return }
        guard !isRecording() else {
            state = .failed(Self.recordingMessage)
            return
        }
        state = .downloading(release)
        do {
            try await installer.download(release)
            // 받는 사이에 녹음을 시작했을 수 있다.
            guard !isRecording() else {
                state = .failed(Self.recordingMessage)
                return
            }
            state = .installing(release)
            try await installer.installAfterQuit(release)
            quit()
        } catch {
            Log.app.error("업데이트 실패: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }

    /// 실패 문구를 닫고 새 버전이 있던 상태로 돌아간다.
    public func dismissFailure() {
        guard case .failed = state else { return }
        state = .idle
    }
}
#endif
