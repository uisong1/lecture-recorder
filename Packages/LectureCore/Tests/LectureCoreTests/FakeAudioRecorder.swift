import Foundation
@testable import LectureCore

@MainActor
final class FakeAudioRecorder: AudioRecording {
    var isRecording = false
    var currentTime: TimeInterval = 0
    private(set) var startedURLs: [URL] = []
    var startError: Error?

    func start(to url: URL) throws {
        if let startError { throw startError }
        startedURLs.append(url)
        isRecording = true
        currentTime = 0
    }

    func stop() -> TimeInterval {
        isRecording = false
        return currentTime
    }
}
