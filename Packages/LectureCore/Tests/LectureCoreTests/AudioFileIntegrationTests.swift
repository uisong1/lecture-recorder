#if canImport(AVFoundation)
import AVFoundation
import Foundation
import Testing
@testable import LectureCore

/// 녹음 설정(AAC .m4a)으로 만든 파일이 실제로 재생되는지 확인한다.
/// CI에는 마이크가 없으므로 사인파를 같은 설정으로 인코딩해 파일을 만든다.
@MainActor
@Suite struct AudioFileIntegrationTests {
    func writeSineWave(seconds: Double, to url: URL) throws {
        let file = try AVAudioFile(forWriting: url, settings: SystemAudioRecorder.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = file.processingFormat
        let frames = AVAudioFrameCount(format.sampleRate * seconds)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let samples = try #require(buffer.floatChannelData?[0])
        for i in 0..<Int(frames) {
            samples[i] = Float(sin(2 * Double.pi * 440 * Double(i) / format.sampleRate) * 0.3)
        }
        try file.write(from: buffer)
    }

    @Test func 녹음_설정으로_만든_파일이_재생된다() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "2026-03-02_1000.m4a")

        try writeSineWave(seconds: 1.5, to: url)

        let player = SystemAudioPlayer()
        try player.load(url)
        #expect(abs(player.duration - 1.5) < 0.2)
        player.play()
        #expect(player.isPlaying)
        player.pause()
        #expect(!player.isPlaying)
        player.stop()
        #expect(player.currentTime == 0)
    }

    @Test func 없는_파일은_재생_오류() {
        let player = SystemAudioPlayer()
        #expect(throws: (any Error).self) {
            try player.load(URL(filePath: "/nonexistent/file.m4a"))
        }
    }
}
#endif
