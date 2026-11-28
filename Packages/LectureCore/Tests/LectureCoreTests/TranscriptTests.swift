import Foundation
import Testing
@testable import LectureCore

@Suite struct TranscriptTests {
    @Test func decodesWorkerJSONAndSortsSegments() throws {
        let json = """
        {"model": "mlx-community/Qwen3-ASR-1.7B-8bit",
         "segments": [
           {"start": 12.5, "end": 15.0, "text": " 두 번째 "},
           {"start": 0, "end": 4.2, "text": "첫 번째"},
           {"start": 20, "end": 21, "text": "   "}
         ]}
        """
        let transcript = try Transcript.decode(Data(json.utf8))
        #expect(transcript.model == "mlx-community/Qwen3-ASR-1.7B-8bit")
        #expect(transcript.segments == [
            TranscriptSegment(start: 0, end: 4.2, text: "첫 번째"),
            TranscriptSegment(start: 12.5, end: 15.0, text: "두 번째"),
        ])
    }

    @Test func fixesNegativeAndBackwardTimes() throws {
        let json = #"{"segments": [{"start": -3, "end": -1, "text": "가"}, {"start": 10, "end": 5, "text": "나"}]}"#
        let transcript = try Transcript.decode(Data(json.utf8))
        #expect(transcript.segments[0].start == 0)
        #expect(transcript.segments[0].end == 0)
        #expect(transcript.segments[1].end == 10)
        #expect(transcript.model == "")
    }

    @Test func rejectsBrokenJSON() {
        #expect(throws: Transcript.DecodeError.invalid) { try Transcript.decode(Data("not json".utf8)) }
        #expect(throws: Transcript.DecodeError.invalid) { try Transcript.decode(Data(#"{"model": "x"}"#.utf8)) }
    }

    @Test func emptySegmentsAreAllowed() throws {
        let transcript = try Transcript.decode(Data(#"{"segments": []}"#.utf8))
        #expect(transcript.segments.isEmpty)
        #expect(transcript.plainText == "")
    }

    @Test func storedRoundTrip() throws {
        let transcript = Transcript(segments: [TranscriptSegment(start: 1, end: 2, text: "안녕")], model: "m")
        #expect(Transcript.stored(try transcript.encoded()) == transcript)
        #expect(Transcript.stored(Data("x".utf8)) == nil)
    }

    let sample = Transcript(segments: [
        TranscriptSegment(start: 0, end: 5, text: "오늘은 Stack을 배워요"),
        TranscriptSegment(start: 5, end: 9, text: "이거 시험에 나옵니다"),
        TranscriptSegment(start: 3700, end: 3705, text: "stack 다시"),
    ], model: "m")

    @Test func segmentIndexAtBoundaries() {
        #expect(sample.segmentIndex(at: 0) == 0)
        #expect(sample.segmentIndex(at: 4.99) == 0)
        #expect(sample.segmentIndex(at: 5) == 1)
        #expect(sample.segmentIndex(at: 100) == 1)
        #expect(sample.segmentIndex(at: 9000) == 2)
        let late = Transcript(segments: [TranscriptSegment(start: 10, end: 12, text: "가")], model: "")
        #expect(late.segmentIndex(at: 3) == nil)
        #expect(Transcript(segments: [], model: "").segmentIndex(at: 3) == nil)
    }

    @Test func searchIgnoresCaseAndSpaces() {
        #expect(sample.matches("STACK") == [0, 2])
        #expect(sample.matches("  시험 ") == [1])
        #expect(sample.matches("   ").isEmpty)
        #expect(sample.matches("없는 말").isEmpty)
    }

    @Test func plainTextHasTimestamps() {
        #expect(sample.plainText == "[0:00] 오늘은 Stack을 배워요\n[0:05] 이거 시험에 나옵니다\n[1:01:40] stack 다시")
    }

    @Test func timestampFormats() {
        #expect(Transcript.timestamp(0) == "0:00")
        #expect(Transcript.timestamp(59.9) == "0:59")
        #expect(Transcript.timestamp(3599) == "59:59")
        #expect(Transcript.timestamp(3600) == "1:00:00")
        #expect(Transcript.timestamp(-5) == "0:00")
    }

    @Test func progressFile() {
        #expect(TranscriptionProgressFile.fraction(from: Data(#"{"done": 3, "total": 12}"#.utf8)) == 0.25)
        #expect(TranscriptionProgressFile.fraction(from: Data(#"{"done": 20, "total": 12}"#.utf8)) == 1)
        #expect(TranscriptionProgressFile.fraction(from: Data(#"{"done": 0, "total": 0}"#.utf8)) == nil)
        #expect(TranscriptionProgressFile.fraction(from: Data("".utf8)) == nil)
    }

    @Test func helperExitMessages() {
        #expect(TranscriptionError.helperExit(20).message.contains("설치"))
        #expect(TranscriptionError.helperExit(99).message.contains("99"))
        #expect(TranscriptionError.helperExit(nil).message.contains("?"))
    }
}
