import Testing
@testable import LectureCore

@Suite struct RecordingScreenNoticesTests {
    func make(
        isRecording: Bool = true,
        isPaused: Bool = false,
        stall: String? = nil,
        storage: String? = nil,
        battery: String? = nil,
        device: String? = nil,
        silent: Bool = false
    ) -> RecordingScreenNotices {
        RecordingScreenNotices(
            isRecording: isRecording, isPaused: isPaused, stallResumeNotice: stall,
            storageWarning: storage, batteryWarning: battery, inputDeviceWarning: device, isInputSilent: silent
        )
    }

    @Test func 경고가_없으면_합친_고정_안내_한_줄만_보인다() {
        let notices = make()
        #expect(notices.warnings.isEmpty)
        #expect(notices.standingNotice == "덮개를 닫으면 멈춥니다 · 창을 닫아도 녹음은 계속됩니다")
    }

    @Test func 경고가_하나라도_있으면_고정_안내는_숨긴다() {
        let notices = make(battery: "배터리 15%")
        #expect(notices.warnings == [.init(kind: .battery, message: "배터리 15%")])
        #expect(notices.standingNotice == nil)
    }

    @Test func 경고가_여럿이면_중요한_순서로_나온다() {
        let notices = make(stall: "멈춰서 이어 녹음", storage: "저장 공간 부족", battery: "배터리 15%", device: "마이크 끊김", silent: true)
        #expect(notices.warnings.map(\.kind) == [.stallResume, .storage, .battery, .inputDevice, .silence])
        #expect(notices.standingNotice == nil)
    }

    @Test func 일시정지_중에는_무음_경고를_내지_않고_고정_안내는_보인다() {
        let notices = make(isPaused: true, silent: true)
        #expect(notices.warnings.isEmpty)
        #expect(notices.standingNotice != nil)
    }

    @Test func 녹음_중이_아니면_고정_안내와_녹음_경고가_없다() {
        let notices = make(isRecording: false, stall: "x", storage: "y", battery: "z", silent: true)
        #expect(notices.warnings.isEmpty)
        #expect(notices.standingNotice == nil)
    }

    @Test func 마이크_경고는_녹음_전에도_보인다() {
        let notices = make(isRecording: false, device: "마이크 끊김")
        #expect(notices.warnings.map(\.kind) == [.inputDevice])
    }
}
