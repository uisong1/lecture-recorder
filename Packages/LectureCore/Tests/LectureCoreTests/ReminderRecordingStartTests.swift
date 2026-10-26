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
}
#endif
