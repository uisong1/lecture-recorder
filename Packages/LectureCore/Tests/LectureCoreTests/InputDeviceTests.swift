import Foundation
import Testing
@testable import LectureCore

@MainActor
final class FakeAudioInput: AudioInputMonitoring {
    var device: AudioInputDevice?
    private var handlers: [@MainActor () -> Void] = []

    init(_ device: AudioInputDevice?) { self.device = device }

    func currentDevice() -> AudioInputDevice? { device }
    func observe(_ handler: @escaping @MainActor () -> Void) { handlers.append(handler) }

    /// 장치를 바꾸고 시스템이 알려 주는 것처럼 변경 알림을 보낸다.
    func change(to newDevice: AudioInputDevice?) {
        device = newDevice
        for handler in handlers { handler() }
    }
}

let builtInMic = AudioInputDevice(id: "builtin", name: "MacBook 마이크")
let usbMic = AudioInputDevice(id: "usb-1", name: "USB 마이크")

@Suite struct InputDeviceAdviceTests {
    @Test func 그대로면_경고하지_않는다() {
        #expect(InputDeviceAdvice.warning(started: builtInMic, current: builtInMic) == nil)
    }

    @Test func 다른_마이크로_바뀌면_두_이름을_알린다() {
        let warning = InputDeviceAdvice.warning(started: usbMic, current: builtInMic)
        #expect(warning?.contains("USB 마이크") == true)
        #expect(warning?.contains("MacBook 마이크") == true)
    }

    @Test func 입력_장치가_없어지면_연결이_끊겼다고_알린다() {
        let warning = InputDeviceAdvice.warning(started: usbMic, current: nil)
        #expect(warning?.contains("연결이 끊겼습니다") == true)
    }

    @Test func 이름이_같아도_고유값이_다르면_다른_장치다() {
        let other = AudioInputDevice(id: "usb-2", name: "USB 마이크")
        #expect(InputDeviceAdvice.warning(started: usbMic, current: other) != nil)
    }

    @Test func 시작할_때_장치를_몰랐으면_경고하지_않는다() {
        #expect(InputDeviceAdvice.warning(started: nil, current: usbMic) == nil)
        #expect(InputDeviceAdvice.warning(started: nil, current: nil) == nil)
    }
}

#if canImport(SwiftData)
import SwiftData

@MainActor
@Suite struct RecordingControllerInputDeviceTests {
    let container: ModelContainer
    let recorder = FakeAudioRecorder()
    let input = FakeAudioInput(usbMic)
    let controller: RecordingController

    init() throws {
        container = try LectureModelContainer.make(inMemory: true)
        let files = FakeFileStore()
        let root = URL(filePath: "/tmp/LectureRecorderTests/Recordings", directoryHint: .isDirectory)
        controller = RecordingController(
            context: container.mainContext,
            recorder: recorder,
            storage: RecordingStorage(root: root, files: files),
            files: files,
            permission: FakeMicrophonePermission(status: .granted),
            inputMonitor: input,
            storageCheckInterval: nil,
            levelCheckInterval: nil,
            calendar: seoulCalendar,
            now: { date(2026, 3, 2, 10, 0) }
        )
    }

    @Test func 대기_중에도_지금_마이크_이름이_보인다() {
        #expect(controller.inputDeviceName == "USB 마이크")
        input.device = nil
        #expect(controller.inputDeviceName == nil)
    }

    @Test func 녹음_중_마이크가_바뀌면_경고하고_녹음은_계속된다() async throws {
        try await controller.start()
        #expect(controller.inputDeviceWarning == nil)

        input.change(to: builtInMic)
        #expect(controller.inputDeviceWarning?.contains("MacBook 마이크") == true)
        #expect(controller.isRecording)
    }

    @Test func 마이크가_끊기면_경고하고_다시_연결하면_사라진다() async throws {
        try await controller.start()
        input.change(to: nil)
        #expect(controller.inputDeviceWarning?.contains("연결이 끊겼습니다") == true)
        #expect(controller.isRecording)

        input.change(to: usbMic)
        #expect(controller.inputDeviceWarning == nil)
    }

    @Test func 녹음_중이_아닐_때_바뀌어도_경고하지_않는다() {
        input.change(to: builtInMic)
        #expect(controller.inputDeviceWarning == nil)
    }

    @Test func 정지하면_경고가_사라지고_다음_녹음은_새_마이크를_기준으로_한다() async throws {
        try await controller.start()
        input.change(to: builtInMic)
        try controller.stop()
        #expect(controller.inputDeviceWarning == nil)

        try await controller.start()
        input.change(to: builtInMic)
        #expect(controller.inputDeviceWarning == nil)
    }
}
#endif
