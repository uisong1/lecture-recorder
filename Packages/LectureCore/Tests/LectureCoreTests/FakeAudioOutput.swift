import Foundation
@testable import LectureCore

@MainActor
final class FakeAudioOutput: AudioOutputInspecting {
    var output: AudioOutputKind
    init(_ output: AudioOutputKind) { self.output = output }
    func currentOutput() -> AudioOutputKind { output }
}
