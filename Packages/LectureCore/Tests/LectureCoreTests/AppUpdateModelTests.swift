#if canImport(SwiftData)
import Foundation
import Testing
@testable import LectureCore

final class FakeUpdateChecker: AppUpdateChecking, @unchecked Sendable {
    let release: AppRelease?
    let error: Error?
    private(set) var calls = 0
    init(release: AppRelease? = nil, error: Error? = nil) {
        self.release = release
        self.error = error
    }
    func latestRelease() async throws -> AppRelease? {
        calls += 1
        if let error { throw error }
        return release
    }
}

@MainActor
final class FakeUpdateInstaller: AppUpdateInstalling {
    var downloadError: Error?
    var installError: Error?
    var onDownload: (() -> Void)?
    private(set) var calls: [String] = []
    func download(_ release: AppRelease) async throws {
        calls.append("download")
        onDownload?()
        if let downloadError { throw downloadError }
    }
    func installAfterQuit(_ release: AppRelease) async throws {
        calls.append("install")
        if let installError { throw installError }
    }
}

func makeUpdateRelease(_ build: Int) -> AppRelease {
    AppRelease(build: build, title: "빌드 \(build)", notes: "", downloadURL: URL(string: "\(AppReleaseParser.allowedDownloadPrefix)build-\(build)/LectureRecorder-\(build).zip")!, sha256: String(repeating: "a", count: 64))
}

@MainActor
@Suite struct AppUpdateModelTests {
    let installer = FakeUpdateInstaller()
    final class Box { var recording = false; var quits = 0 }
    let box = Box()

    func makeModel(current: Int = 10, checker: FakeUpdateChecker) -> AppUpdateModel {
        let box = box
        return AppUpdateModel(currentBuild: current, checker: checker, installer: installer, isRecording: { box.recording }, quit: { box.quits += 1 })
    }

    @Test func 더_높은_빌드가_있으면_새_버전으로_알린다() async {
        let model = makeModel(checker: FakeUpdateChecker(release: makeUpdateRelease(11)))
        await model.check(now: Date())
        #expect(model.availableRelease?.build == 11)
    }

    @Test func 같거나_낮은_빌드면_최신이다() async {
        let same = makeModel(checker: FakeUpdateChecker(release: makeUpdateRelease(10)))
        await same.check(now: Date())
        #expect(same.state == .upToDate)
        let none = makeModel(checker: FakeUpdateChecker(release: nil))
        await none.check(now: Date())
        #expect(none.state == .upToDate)
    }

    @Test func 확인_실패는_문구로_알린다() async {
        let model = makeModel(checker: FakeUpdateChecker(error: URLError(.notConnectedToInternet)))
        await model.check(now: Date())
        guard case .failed = model.state else { Issue.record("실패 상태여야 함"); return }
    }

    @Test func 자동_확인은_실패해도_조용하다() async {
        let model = makeModel(checker: FakeUpdateChecker(error: URLError(.notConnectedToInternet)))
        await model.checkAutomaticallyIfDue(now: Date())
        #expect(model.state == .idle)
    }

    @Test func 자동_확인은_하루_안에는_다시_하지_않는다() async {
        let checker = FakeUpdateChecker(release: nil)
        let model = makeModel(checker: checker)
        let start = Date(timeIntervalSince1970: 1_000_000)
        await model.checkAutomaticallyIfDue(now: start)
        await model.checkAutomaticallyIfDue(now: start.addingTimeInterval(3600))
        #expect(checker.calls == 1)
        await model.checkAutomaticallyIfDue(now: start.addingTimeInterval(AppUpdateModel.automaticInterval + 1))
        #expect(checker.calls == 2)
    }

    @Test func 설치는_받고_도우미를_부른_뒤_앱을_종료한다() async {
        let model = makeModel(checker: FakeUpdateChecker(release: makeUpdateRelease(11)))
        await model.check(now: Date())
        await model.install()
        #expect(installer.calls == ["download", "install"])
        #expect(box.quits == 1)
        #expect(model.state == .installing(makeUpdateRelease(11)))
    }

    @Test func 녹음_중에는_받지도_종료하지도_않는다() async {
        let model = makeModel(checker: FakeUpdateChecker(release: makeUpdateRelease(11)))
        await model.check(now: Date())
        box.recording = true
        #expect(!model.canInstall)
        await model.install()
        #expect(installer.calls.isEmpty)
        #expect(box.quits == 0)
        #expect(model.state == .failed(AppUpdateModel.recordingMessage))
    }

    @Test func 받는_사이_녹음을_시작하면_설치하지_않는다() async {
        let model = makeModel(checker: FakeUpdateChecker(release: makeUpdateRelease(11)))
        await model.check(now: Date())
        let box = box
        installer.onDownload = { box.recording = true }
        await model.install()
        #expect(installer.calls == ["download"])
        #expect(box.quits == 0)
        #expect(model.state == .failed(AppUpdateModel.recordingMessage))
    }

    @Test func 도우미가_없으면_안내_문구를_보인다() async {
        let model = makeModel(checker: FakeUpdateChecker(release: makeUpdateRelease(11)))
        await model.check(now: Date())
        installer.downloadError = AppUpdateError.helperMissing
        await model.install()
        #expect(box.quits == 0)
        #expect(model.state == .failed(AppUpdateError.helperMissing.errorDescription ?? ""))
    }

    @Test func 설치_도우미가_실패하면_종료하지_않는다() async {
        let model = makeModel(checker: FakeUpdateChecker(release: makeUpdateRelease(11)))
        await model.check(now: Date())
        installer.installError = AppUpdateError.failed("실패")
        await model.install()
        #expect(box.quits == 0)
        #expect(model.state == .failed("실패"))
    }

    @Test func 새_버전이_없으면_설치_버튼을_눌러도_아무것도_하지_않는다() async {
        let model = makeModel(checker: FakeUpdateChecker(release: nil))
        await model.install()
        #expect(installer.calls.isEmpty)
        #expect(!model.canInstall)
    }
}
#endif
