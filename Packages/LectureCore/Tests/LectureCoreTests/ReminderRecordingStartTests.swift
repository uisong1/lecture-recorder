#if canImport(SwiftData)
import Foundation
import SwiftData
import Testing
@testable import LectureCore

/// 알림 버튼으로 시작하는 녹음: 알림에 적힌 과목으로 시작하고, 이미 녹음 중이거나 과목이 없으면 건드리지 않는다.
extension RecordingControllerTests {
    @Test func 알림에_적힌_과목으로_녹음을_시작한다() async throws {
        _ = try addBackToBackClasses()
        // 시간표로는 자료구조 시간이지만 알림은 선형대수를 가리킨다.
        let controller = makeController(at: date(2026, 3, 2, 10, 0))

        let outcome = await controller.startRecording(forSubjectNamed: "선형대수")

        #expect(outcome == .started)
        #expect(controller.isRecording)
        #expect(controller.currentSubjectName == "선형대수")
        #expect(controller.errorMessage == nil)
    }

    @Test func 이미_녹음_중이면_알림_버튼을_무시한다() async throws {
        _ = try addBackToBackClasses()
        let controller = makeController(at: date(2026, 3, 2, 10, 0))
        try await controller.start()

        let outcome = await controller.startRecording(forSubjectNamed: "선형대수")

        #expect(outcome == .alreadyRecording)
        #expect(controller.currentSubjectName == "자료구조")
        #expect(recorder.startedURLs.count == 1)
    }

    @Test func 과목이_지워진_알림은_녹음을_시작하지_않고_이유를_남긴다() async throws {
        _ = try addSubjectWithSlot()
        let controller = makeController(at: date(2026, 3, 2, 10, 0))

        let outcome = await controller.startRecording(forSubjectNamed: "지워진 과목")

        #expect(outcome == .subjectMissing)
        #expect(!controller.isRecording)
        #expect(controller.errorMessage != nil)
        #expect(recorder.startedURLs.isEmpty)
    }

    @Test func 마이크_권한이_없으면_녹음하지_않고_안내를_남긴다() async throws {
        _ = try addSubjectWithSlot()
        permission.status = .denied
        permission.answer = .denied
        let controller = makeController(at: date(2026, 3, 2, 10, 0))

        let outcome = await controller.startRecording(forSubjectNamed: "자료구조")

        #expect(outcome == .failed)
        #expect(!controller.isRecording)
        #expect(controller.errorMessage == RecordingError.permissionDenied.errorDescription)
        #expect(controller.subjectChoice == .automatic)
    }

    // MARK: 정지 직후 이어서 녹음

    @Test func 정지_직후_이어서_녹음하면_방금_저장한_녹음의_과목으로_시작한다() async throws {
        _ = try addBackToBackClasses()
        let clock = TestClock(date(2026, 3, 2, 10, 0))
        let controller = makeController(at: clock.now, clock: clock)
        try await controller.start()
        clock.advance(by: 20 * 60)
        _ = try controller.stop()

        // 시간표로는 선형대수 시간이 됐지만 이어서 녹음은 방금 전 과목을 쓴다.
        clock.advance(by: 56 * 60)
        await controller.continueAfterStop()

        #expect(controller.isRecording)
        #expect(controller.currentSubjectName == "자료구조")
        #expect(recorder.startedURLs.count == 2)
        #expect(controller.subjectChoice == .automatic)
        #expect(controller.errorMessage == nil)
    }

    @Test func 방금_저장한_녹음이_미분류면_미분류로_이어서_녹음한다() async throws {
        let controller = makeController(at: date(2026, 3, 2, 15, 0))  // 수업 없는 시간
        try await controller.start()
        _ = try controller.stop()

        await controller.continueAfterStop()

        #expect(controller.isRecording)
        #expect(controller.currentSubjectName == SubjectManager.unclassifiedName)
    }

    @Test func 저장한_녹음이_없거나_이미_녹음_중이면_이어서_녹음은_아무것도_하지_않는다() async throws {
        _ = try addSubjectWithSlot()
        let controller = makeController(at: date(2026, 3, 2, 10, 0))
        await controller.continueAfterStop()
        #expect(!controller.isRecording)
        #expect(recorder.startedURLs.isEmpty)

        try await controller.start()
        await controller.continueAfterStop()
        #expect(recorder.startedURLs.count == 1)
    }

    @Test func 이어서_녹음을_시작하지_못하면_이유를_남기고_과목_선택을_되돌린다() async throws {
        _ = try addSubjectWithSlot()
        let controller = makeController(at: date(2026, 3, 2, 10, 0))
        try await controller.start()
        _ = try controller.stop()
        permission.status = .denied
        permission.answer = .denied

        await controller.continueAfterStop()

        #expect(!controller.isRecording)
        #expect(controller.errorMessage == RecordingError.permissionDenied.errorDescription)
        #expect(controller.subjectChoice == .automatic)
    }
}
#endif
