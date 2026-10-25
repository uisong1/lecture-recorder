import Foundation
import Testing
@testable import LectureCore

@MainActor
final class FakeQuitTarget: QuitGuardTarget {
    var isRecording: Bool
    var stopError: Error?
    private(set) var stopCount = 0

    init(isRecording: Bool) { self.isRecording = isRecording }

    func stopForQuit() throws {
        stopCount += 1
        if let stopError { throw stopError }
        isRecording = false
    }
}

struct DiskFull: Error, LocalizedError {
    var errorDescription: String? { "저장 공간 부족" }
}

@MainActor
@Suite struct QuitGuardTests {
    @Test func 녹음_중이_아니면_바로_종료한다() {
        let guardian = QuitGuard(target: FakeQuitTarget(isRecording: false))
        #expect(guardian.requestQuit() == .quitNow)
    }

    @Test func 녹음_중이면_종료_전에_묻는다() {
        let target = FakeQuitTarget(isRecording: true)
        let guardian = QuitGuard(target: target)
        #expect(guardian.requestQuit() == .askUser)
        #expect(target.stopCount == 0)
    }

    @Test func 취소하면_녹음이_계속된다() {
        let target = FakeQuitTarget(isRecording: true)
        let guardian = QuitGuard(target: target)
        #expect(guardian.resolve(.keepRecording) == .keepRunning(errorMessage: nil))
        #expect(target.isRecording)
        #expect(target.stopCount == 0)
    }

    @Test func 저장하고_종료를_고르면_녹음을_저장한_뒤_종료한다() {
        let target = FakeQuitTarget(isRecording: true)
        let guardian = QuitGuard(target: target)
        #expect(guardian.resolve(.saveAndQuit) == .quit)
        #expect(target.stopCount == 1)
        #expect(!target.isRecording)
    }

    @Test func 저장에_실패하면_종료하지_않고_이유를_알린다() {
        let target = FakeQuitTarget(isRecording: true)
        target.stopError = DiskFull()
        let guardian = QuitGuard(target: target)
        #expect(guardian.resolve(.saveAndQuit) == .keepRunning(errorMessage: "녹음을 저장하지 못해 종료하지 않았습니다: 저장 공간 부족"))
        #expect(target.isRecording)
    }

    @Test func 확인_창이_떠_있는_사이_녹음이_끝났으면_저장_없이_종료한다() {
        let target = FakeQuitTarget(isRecording: true)
        let guardian = QuitGuard(target: target)
        #expect(guardian.requestQuit() == .askUser)
        target.isRecording = false
        #expect(guardian.resolve(.saveAndQuit) == .quit)
        #expect(target.stopCount == 0)
    }
}
