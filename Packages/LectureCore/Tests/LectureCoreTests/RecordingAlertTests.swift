import Foundation
import Testing
@testable import LectureCore

@Suite struct RecordingAlertContentTests {
    @Test func 알림마다_식별자와_문구가_다르다() {
        let alerts = RecordingAlert.allCases
        #expect(Set(alerts.map(\.identifier)).count == alerts.count)
        for alert in alerts {
            #expect(!alert.title.isEmpty)
            #expect(!alert.body.isEmpty)
        }
    }
}

#if canImport(SwiftData)
import SwiftData

@MainActor
@Suite struct RecordingAlertTests {
    let container: ModelContainer
    let recorder = FakeAudioRecorder()
    let files = FakeFileStore()
    let notifier = FakeNotificationScheduler()
    let lifecycle = FakeLifecycleEvents()
    let input = FakeAudioInput(usbMic)
    let clock = TestClock(date(2026, 3, 2, 10, 0))
    let controller: RecordingController

    init() throws {
        container = try LectureModelContainer.make(inMemory: true)
        let root = URL(filePath: "/tmp/LectureRecorderTests/Recordings", directoryHint: .isDirectory)
        let clock = clock
        controller = RecordingController(
            context: container.mainContext,
            recorder: recorder,
            storage: RecordingStorage(root: root, files: files),
            files: files,
            permission: FakeMicrophonePermission(status: .granted),
            inputMonitor: input,
            overrunNotifier: notifier,
            lifecycle: lifecycle,
            storageCheckInterval: nil,
            levelCheckInterval: nil,
            calendar: seoulCalendar,
            now: { clock.now }
        )
    }

    /// 알림을 보내는 작업이 끝나도록 잠시 양보한다.
    private func settle() async {
        for _ in 0..<5 { await Task.yield() }
    }

    @Test func 잠자기로_저장되면_알림을_한_번_보낸다() async throws {
        try await controller.start()
        lifecycle.send(.willSleep)
        await settle()

        #expect(notifier.notifiedIdentifiers == [RecordingAlert.savedBeforeSleep.identifier])
        #expect(notifier.notified.first?.title.contains("여기까지 저장") == true)
    }

    @Test func 종료로_저장되면_알림을_보낸다() async throws {
        try await controller.start()
        lifecycle.send(.willTerminate)
        await settle()
        #expect(notifier.notifiedIdentifiers == [RecordingAlert.savedBeforeQuit.identifier])
    }

    @Test func 저장_공간이_바닥나_자동_정지되면_알림을_보낸다() async throws {
        try await controller.start()
        files.capacity = RecordingController.storageCriticalBytes - 1
        controller.checkStorage()
        await settle()
        #expect(notifier.notifiedIdentifiers == [RecordingAlert.storageFull.identifier])
    }

    @Test func 저장_공간_경고만_있을_때는_알림을_보내지_않는다() async throws {
        try await controller.start()
        files.capacity = RecordingController.storageWarningBytes - 1
        controller.checkStorage()
        await settle()
        #expect(controller.storageWarning != nil)
        #expect(notifier.notified.isEmpty)
    }

    @Test func 녹음기가_멈추면_이어_녹음한다는_알림을_보내고_또_멈추면_멈춘_알림을_보낸다() async throws {
        try await controller.start()
        recorder.hasEnded = true
        controller.checkRecorderHealth()
        await settle()
        #expect(notifier.notifiedIdentifiers == [RecordingAlert.recorderResumed.identifier])
        controller.checkRecorderHealth()
        await settle()
        #expect(notifier.notifiedIdentifiers == [RecordingAlert.recorderResumed.identifier, RecordingAlert.recorderStalled.identifier])
    }

    @Test func 마이크가_바뀌면_알림을_한_번만_보낸다() async throws {
        try await controller.start()
        input.change(to: builtInMic)
        input.change(to: nil)
        input.change(to: builtInMic)
        await settle()
        #expect(notifier.notifiedIdentifiers == [RecordingAlert.inputDeviceChanged.identifier])
        #expect(controller.isRecording)
    }

    @Test func 무음_경고가_처음_뜰_때만_알림을_보낸다() async throws {
        try await controller.start()
        recorder.inputLevel = 0
        controller.sampleInputLevel()
        clock.advance(by: 11)
        controller.sampleInputLevel()
        controller.sampleInputLevel()
        clock.advance(by: 60)
        controller.sampleInputLevel()
        await settle()
        #expect(controller.isInputSilent)
        #expect(notifier.notifiedIdentifiers == [RecordingAlert.inputSilent.identifier])
    }

    @Test func 소리가_정상이면_알림을_보내지_않는다() async throws {
        try await controller.start()
        recorder.inputLevel = 0.5
        controller.sampleInputLevel()
        clock.advance(by: 60)
        controller.sampleInputLevel()
        await settle()
        #expect(notifier.notified.isEmpty)
    }

    @Test func 새_녹음에서는_같은_종류의_알림을_다시_보낼_수_있다() async throws {
        try await controller.start()
        lifecycle.send(.willSleep)
        try await controller.start()
        lifecycle.send(.willSleep)
        await settle()
        #expect(notifier.notifiedIdentifiers == [RecordingAlert.savedBeforeSleep.identifier, RecordingAlert.savedBeforeSleep.identifier])
    }

    @Test func 서로_다른_상황은_각각_한_번씩_보낸다() async throws {
        try await controller.start()
        input.change(to: builtInMic)
        recorder.inputLevel = 0
        controller.sampleInputLevel()
        clock.advance(by: 11)
        controller.sampleInputLevel()
        lifecycle.send(.willSleep)
        await settle()
        #expect(Set(notifier.notifiedIdentifiers) == [
            RecordingAlert.inputDeviceChanged.identifier,
            RecordingAlert.inputSilent.identifier,
            RecordingAlert.savedBeforeSleep.identifier,
        ])
        #expect(notifier.notifiedIdentifiers.count == 3)
    }

    @Test func 알림을_허용하지_않았으면_조용히_넘어가고_권한을_묻지_않는다() async throws {
        notifier.authorized = false
        try await controller.start()
        lifecycle.send(.willSleep)
        await settle()
        #expect(notifier.notified.isEmpty)
        #expect(notifier.authorizationRequests == 0)
        // 화면 안내는 알림과 별개로 남는다.
        #expect(controller.interruptionNotice != nil)
    }

    @Test func 일시정지가_십분_넘으면_안내하고_알림을_한_번_보낸다() async throws {
        try await controller.start()
        try controller.pause()

        clock.advance(by: 9 * 60 + 59)
        controller.checkPaused()
        await settle()
        #expect(controller.pausedNotice == nil)
        #expect(notifier.notified.isEmpty)

        clock.advance(by: 1)  // 10분 정각
        controller.checkPaused()
        controller.checkPaused()
        await settle()
        #expect(controller.pausedNotice == PausedAdvice.notice)
        #expect(notifier.notifiedIdentifiers == [RecordingAlert.pausedTooLong.identifier])
        #expect(notifier.notified.first?.body == PausedAdvice.notice)
        #expect(controller.menuBarStatus.pausedNotice == PausedAdvice.notice)
    }

    @Test func 재개하면_안내가_사라지고_다시_일시정지하면_새로_센다() async throws {
        try await controller.start()
        try controller.pause()
        clock.advance(by: 10 * 60)
        controller.checkPaused()
        try controller.resume()
        #expect(controller.pausedNotice == nil)
        #expect(controller.menuBarStatus.pausedNotice == nil)

        try controller.pause()
        clock.advance(by: 9 * 60 + 59)
        controller.checkPaused()
        #expect(controller.pausedNotice == nil)

        clock.advance(by: 1)
        controller.checkPaused()
        await settle()
        // 일시정지마다 한 번씩이므로 모두 두 번.
        #expect(notifier.notifiedIdentifiers == [RecordingAlert.pausedTooLong.identifier, RecordingAlert.pausedTooLong.identifier])
    }

    @Test func 정지하면_일시정지_안내가_해제된다() async throws {
        try await controller.start()
        try controller.pause()
        clock.advance(by: 20 * 60)
        #expect(controller.pausedNotice != nil)
        try controller.stop()
        #expect(controller.pausedNotice == nil)
        controller.checkPaused()
        await settle()
        #expect(notifier.notified.isEmpty)
    }

    @Test func 녹음_중이_아니거나_녹음_중이면_아무_일도_없다() async throws {
        clock.advance(by: 3600)
        controller.checkPaused()
        try await controller.start()
        clock.advance(by: 3600)
        controller.checkPaused()
        await settle()
        #expect(controller.pausedNotice == nil)
        #expect(notifier.notified.isEmpty)
    }

    @Test func 알림을_허용하지_않아도_일시정지_안내는_화면에_남는다() async throws {
        notifier.authorized = false
        try await controller.start()
        try controller.pause()
        clock.advance(by: 10 * 60)
        controller.checkPaused()
        await settle()
        #expect(controller.pausedNotice != nil)
        #expect(notifier.notified.isEmpty)
    }
}
#endif
