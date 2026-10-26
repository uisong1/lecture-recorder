#if canImport(SwiftData)
import Foundation
import Testing
@testable import LectureCore

@MainActor
@Suite struct RecordingAlertRaiserTests {
    let notifier = FakeNotificationScheduler()

    private func settle() async {
        for _ in 0..<5 { await Task.yield() }
    }

    @Test func 같은_종류는_한_번만_보낸다() async {
        let raiser = RecordingAlertRaiser(notifier: notifier)

        raiser.raise(.inputSilent)
        raiser.raise(.inputSilent)
        await settle()

        #expect(notifier.notifiedIdentifiers == [RecordingAlert.inputSilent.identifier])
    }

    @Test func 다른_종류는_각각_보낸다() async {
        let raiser = RecordingAlertRaiser(notifier: notifier)

        raiser.raise(.inputSilent)
        raiser.raise(.storageFull)
        await settle()

        #expect(Set(notifier.notifiedIdentifiers) == [RecordingAlert.inputSilent.identifier, RecordingAlert.storageFull.identifier])
        #expect(notifier.notifiedIdentifiers.count == 2)
    }

    @Test func reset_하면_같은_종류를_다시_보낼_수_있다() async {
        let raiser = RecordingAlertRaiser(notifier: notifier)

        raiser.raise(.recorderStalled)
        raiser.reset()
        raiser.raise(.recorderStalled)
        await settle()

        #expect(notifier.notifiedIdentifiers.count == 2)
    }

    @Test func 문구를_따로_주면_그_문구를_쓴다() async {
        let raiser = RecordingAlertRaiser(notifier: notifier)

        raiser.raise(.inputDeviceChanged, body: "마이크 이름이 바뀜")
        await settle()

        #expect(notifier.notified.first?.body == "마이크 이름이 바뀜")
        #expect(notifier.notified.first?.title == RecordingAlert.inputDeviceChanged.title)
    }

    @Test func 알림을_허용하지_않았으면_아무것도_보내지_않는다() async {
        notifier.authorized = false
        let raiser = RecordingAlertRaiser(notifier: notifier)

        raiser.raise(.storageFull)
        await settle()

        #expect(notifier.notified.isEmpty)
    }

    @Test func 알림기가_없어도_문제없이_넘어간다() async {
        let raiser = RecordingAlertRaiser(notifier: nil)

        raiser.raise(.storageFull)
        raiser.reset()
        raiser.raise(.storageFull)

        #expect(notifier.notified.isEmpty)
    }

    @Test func rearm_하면_그_종류만_다시_보낼_수_있다() async {
        let raiser = RecordingAlertRaiser(notifier: notifier)

        raiser.raise(.pausedTooLong)
        raiser.raise(.storageFull)
        raiser.rearm(.pausedTooLong)
        raiser.raise(.pausedTooLong)
        raiser.raise(.storageFull)
        await settle()

        #expect(notifier.notifiedIdentifiers.filter { $0 == RecordingAlert.pausedTooLong.identifier }.count == 2)
        #expect(notifier.notifiedIdentifiers.filter { $0 == RecordingAlert.storageFull.identifier }.count == 1)
    }
}
#endif
