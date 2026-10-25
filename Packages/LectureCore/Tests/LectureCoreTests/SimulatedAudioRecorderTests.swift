import Foundation
import Testing
@testable import LectureCore

@MainActor
@Suite struct SimulatedAudioRecorderTests {
    @Test func 시계로_경과_시간을_계산한다() throws {
        var now = Date(timeIntervalSince1970: 1_000)
        let recorder = SimulatedAudioRecorder(now: { now })
        try recorder.start(to: URL(filePath: "/tmp/a.m4a"))
        now += 42
        #expect(recorder.isRecording)
        #expect(recorder.currentTime == 42)
        #expect(recorder.stop() == 42)
        #expect(!recorder.isRecording)
        #expect(recorder.currentTime == 0)
    }
}
