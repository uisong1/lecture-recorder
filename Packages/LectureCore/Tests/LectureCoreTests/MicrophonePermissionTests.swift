import Foundation
import Testing
@testable import LectureCore

final class FakeMicrophonePermission: MicrophonePermissionProviding, @unchecked Sendable {
    var status: MicrophonePermissionStatus
    var answer: MicrophonePermissionStatus
    private(set) var requestCount = 0

    init(status: MicrophonePermissionStatus, answer: MicrophonePermissionStatus = .granted) {
        self.status = status
        self.answer = answer
    }

    func currentStatus() -> MicrophonePermissionStatus { status }

    func request() async -> MicrophonePermissionStatus {
        requestCount += 1
        status = answer
        return answer
    }
}

/// 권한 창이 떠 있는 것처럼 `answer(_:)`를 부를 때까지 답하지 않는 가짜 권한.
final class GatedMicrophonePermission: MicrophonePermissionProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var status: MicrophonePermissionStatus = .notDetermined
    private var pending: CheckedContinuation<MicrophonePermissionStatus, Never>?
    private var askedWaiters: [CheckedContinuation<Void, Never>] = []
    private var _askCount = 0

    var askCount: Int { lock.withLock { _askCount } }

    func currentStatus() -> MicrophonePermissionStatus { lock.withLock { status } }

    func request() async -> MicrophonePermissionStatus {
        await withCheckedContinuation { continuation in
            let waiters = lock.withLock {
                _askCount += 1
                pending = continuation
                let waiters = askedWaiters
                askedWaiters = []
                return waiters
            }
            waiters.forEach { $0.resume() }
        }
    }

    /// 권한을 묻기 시작할 때까지 기다린다.
    func waitUntilAsked() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let asked = lock.withLock {
                if pending != nil { return true }
                askedWaiters.append(continuation)
                return false
            }
            if asked { continuation.resume() }
        }
    }

    func answer(_ answer: MicrophonePermissionStatus) {
        let continuation = lock.withLock {
            status = answer
            let continuation = pending
            pending = nil
            return continuation
        }
        continuation?.resume(returning: answer)
    }
}

@Suite struct MicrophonePermissionTests {
    @Test func 처음이면_권한을_요청한다() async {
        let fake = FakeMicrophonePermission(status: .notDetermined, answer: .granted)
        #expect(await fake.requestIfNeeded() == .granted)
        #expect(fake.requestCount == 1)
    }

    @Test func 이미_허용했으면_다시_묻지_않는다() async {
        let fake = FakeMicrophonePermission(status: .granted)
        #expect(await fake.requestIfNeeded() == .granted)
        #expect(fake.requestCount == 0)
    }

    @Test func 이미_거부했으면_다시_묻지_않고_거부를_돌려준다() async {
        let fake = FakeMicrophonePermission(status: .denied)
        #expect(await fake.requestIfNeeded() == .denied)
        #expect(fake.requestCount == 0)
    }
}
