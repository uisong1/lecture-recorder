import Foundation
@testable import LectureCore

@MainActor
final class FakeAudioPlayer: AudioPlaying {
    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    private(set) var loadedURLs: [URL] = []
    var rate: Float = 1

    func seek(to time: TimeInterval) {
        currentTime = min(max(time, 0), duration)
    }

    var loadError: Error?
    var durationForNextLoad: TimeInterval = 60

    func load(_ url: URL) throws {
        if let loadError { throw loadError }
        loadedURLs.append(url)
        duration = durationForNextLoad
        currentTime = 0
        isPlaying = false
    }

    func play() {
        guard !loadedURLs.isEmpty else { return }
        isPlaying = true
    }

    func pause() { isPlaying = false }

    func stop() {
        isPlaying = false
        currentTime = 0
    }
}
