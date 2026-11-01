import Foundation
import LectureCore

/// 새 앱을 받아 바꿔 끼우는 일은 샌드박스 밖에서 해야 해서, install.sh가 정해진 위치에 둔 도우미 스크립트를 `NSUserUnixTask`로 실행한다.
/// 이 위치(~/Library/Application Scripts/<번들 ID>/)의 스크립트만 실행할 수 있고, 사용자가 직접 설치한 것이어야 한다.
@MainActor
final class UserScriptUpdateInstaller: AppUpdateInstalling {
    private func helperURL() throws -> URL {
        let folder = try FileManager.default.url(for: .applicationScriptsDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        return folder.appending(path: "update.sh")
    }

    /// 응용 프로그램 폴더 등에 설치된 `LectureRecorder.app`일 때만 바꿀 수 있다 (Xcode에서 실행한 빌드는 제외).
    private func checkRunningFromInstalledApp() throws {
        guard Bundle.main.bundleURL.lastPathComponent == "LectureRecorder.app",
              !Bundle.main.bundleURL.path.contains("/DerivedData/") else {
            throw AppUpdateError.failed("설치된 앱에서만 업데이트할 수 있습니다. Xcode에서 연 앱이라면 install.sh로 설치한 앱을 열어 주세요.")
        }
    }

    func download(_ release: AppRelease) async throws {
        try checkRunningFromInstalledApp()
        try await run(["download", release.downloadURL.absoluteString, release.sha256, String(release.build)])
    }

    func installAfterQuit(_ release: AppRelease) async throws {
        try checkRunningFromInstalledApp()
        try await run(["install", String(release.build), String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundleURL.path])
    }

    private func run(_ arguments: [String]) async throws {
        let task: NSUserUnixTask
        do {
            task = try NSUserUnixTask(url: try helperURL())
        } catch {
            Log.app.error("업데이트 도우미를 열지 못함: \(error.localizedDescription, privacy: .public)")
            throw AppUpdateError.helperMissing
        }
        let failure: Error? = await withCheckedContinuation { continuation in
            task.execute(withArguments: arguments) { error in
                continuation.resume(returning: error)
            }
        }
        guard let failure else { return }
        let status = (failure as NSError).userInfo["NSUnixExitStatus"] as? Int
        Log.app.error("업데이트 도우미 실패(종료 코드 \(status ?? -1, privacy: .public)): \(failure.localizedDescription, privacy: .public)")
        throw AppUpdateError.failed(Self.message(forExitStatus: status))
    }

    static func message(forExitStatus status: Int?) -> String {
        switch status {
        case 10: "새 버전을 받지 못했습니다. 인터넷 연결을 확인한 뒤 다시 시도해 주세요."
        case 11: "받은 파일이 올바르지 않아 설치하지 않았습니다. 잠시 뒤 다시 시도해 주세요."
        case 12: "받은 앱을 확인하지 못해 설치하지 않았습니다. 기존 앱은 그대로입니다."
        case 13: "받아 둔 새 버전을 찾지 못했습니다. 다시 시도해 주세요."
        case 14: "앱을 바꾸지 못했습니다. 기존 앱은 그대로입니다."
        default: "업데이트하지 못했습니다. 기존 앱은 그대로입니다. 문제가 계속되면 ./scripts/install.sh를 실행해 주세요."
        }
    }
}
