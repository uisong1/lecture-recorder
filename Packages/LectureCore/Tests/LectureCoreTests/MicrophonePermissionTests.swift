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
