import Foundation
import Testing
@testable import LectureCore

@MainActor
final class FakePowerStatus: PowerStatusProviding {
    var status: PowerStatus?
    init(_ status: PowerStatus?) { self.status = status }
    func current() -> PowerStatus? { status }
}

@Suite struct BatteryAdviceTests {
    @Test func 배터리_19퍼센트이고_충전기가_없으면_경고한다() {
        let warning = BatteryAdvice.recordingWarning(for: PowerStatus(batteryPercent: 19, isPluggedIn: false))
        #expect(warning?.contains("19%") == true)
    }

    @Test func 정확히_20퍼센트는_경고하지_않는다() {
        #expect(BatteryAdvice.recordingWarning(for: PowerStatus(batteryPercent: 20, isPluggedIn: false)) == nil)
    }

    @Test func 충전기가_연결되어_있으면_낮아도_경고하지_않는다() {
        #expect(BatteryAdvice.recordingWarning(for: PowerStatus(batteryPercent: 5, isPluggedIn: true)) == nil)
        #expect(BatteryAdvice.recordingWarning(for: PowerStatus(batteryPercent: 0, isPluggedIn: true)) == nil)
    }

    @Test func 배터리가_없는_맥에서는_경고하지_않는다() {
        #expect(BatteryAdvice.recordingWarning(for: nil) == nil)
        #expect(BatteryAdvice.preRecordingAdvice(for: nil) == nil)
    }

    @Test func 배터리만_쓰는_중이면_시작_전에_충전을_권한다() {
        #expect(BatteryAdvice.preRecordingAdvice(for: PowerStatus(batteryPercent: 80, isPluggedIn: false)) != nil)
    }

    @Test func 충전기가_연결되어_있으면_시작_전_권장을_보이지_않는다() {
        #expect(BatteryAdvice.preRecordingAdvice(for: PowerStatus(batteryPercent: 80, isPluggedIn: true)) == nil)
    }

    @Test func 덮개_안내_문구() {
        #expect(BatteryAdvice.lidNotice == "덮개를 닫으면 녹음이 멈춥니다")
    }
}

#if canImport(SwiftData)
import SwiftData

@MainActor
@Suite struct RecordingControllerPowerTests {
    let container: ModelContainer
    let recorder = FakeAudioRecorder()
    let power = FakePowerStatus(PowerStatus(batteryPercent: 80, isPluggedIn: false))
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
            powerStatus: power,
            storageCheckInterval: nil,
            levelCheckInterval: nil,
            calendar: seoulCalendar,
            now: { date(2026, 3, 2, 10, 0) }
        )
    }

    @Test func 녹음_전에는_충전_권장만_보인다() {
        #expect(controller.preRecordingAdvice != nil)
        #expect(controller.batteryWarning == nil)
    }

    @Test func 녹음_중에는_충전_권장이_사라지고_낮은_배터리만_경고한다() async throws {
        try await controller.start()
        #expect(controller.preRecordingAdvice == nil)
        #expect(controller.batteryWarning == nil)

        power.status = PowerStatus(batteryPercent: 19, isPluggedIn: false)
        #expect(controller.batteryWarning != nil)

        power.status = PowerStatus(batteryPercent: 19, isPluggedIn: true)
        #expect(controller.batteryWarning == nil)
    }

    @Test func 정지하면_경고가_사라지고_충전_권장이_돌아온다() async throws {
        power.status = PowerStatus(batteryPercent: 10, isPluggedIn: false)
        try await controller.start()
        #expect(controller.batteryWarning != nil)
        try controller.stop()
        #expect(controller.batteryWarning == nil)
        #expect(controller.preRecordingAdvice != nil)
    }
}
#endif
