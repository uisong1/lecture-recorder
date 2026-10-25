import Foundation
@testable import LectureCore

@MainActor
final class FakeAudioRecorder: AudioRecording {
    var isRecording = false
    private(set) var isPaused = false
    var resumeError: Error?
    var currentTime: TimeInterval = 0
    private(set) var startedURLs: [URL] = []
    var startError: Error?

    func start(to url: URL) throws {
        if let startError { throw startError }
        startedURLs.append(url)
        isRecording = true
        currentTime = 0
    }

    func pause() { isPaused = true }

    func resume() throws {
        if let resumeError { throw resumeError }
        isPaused = false
    }

    func stop() -> TimeInterval {
        isRecording = false
        isPaused = false
        return currentTime
    }
}
