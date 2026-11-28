import Foundation

/// 전사 결과의 한 구간. 시각은 녹음 처음부터의 초다.
public struct TranscriptSegment: Codable, Equatable, Sendable {
    public var start: TimeInterval
    public var end: TimeInterval
    public var text: String

    public init(start: TimeInterval, end: TimeInterval, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

/// 녹음 하나의 전사 결과. 전사 도우미(mlx-audio, Qwen3-ASR)가 쓴 JSON을 읽어 만든다.
public struct Transcript: Codable, Equatable, Sendable {
    public var segments: [TranscriptSegment]
    /// 전사에 쓴 모델 이름 (예: mlx-community/Qwen3-ASR-1.7B-8bit).
    public var model: String

    public init(segments: [TranscriptSegment], model: String) {
        self.segments = segments
        self.model = model
    }

    public enum DecodeError: Error, Equatable {
        case invalid
    }

    /// 도우미가 쓴 JSON(`{"model": "...", "segments": [{"start", "end", "text"}]}`)을 읽는다.
    /// 빈 글자 구간은 빼고, 시작 시각 순서로 정렬한다. 시각이 음수거나 끝이 시작보다 앞이면 바로잡는다.
    public static func decode(_ data: Data) throws -> Transcript {
        struct Raw: Decodable {
            struct Segment: Decodable {
                var start: Double?
                var end: Double?
                var text: String?
            }
            var model: String?
            var segments: [Segment]?
        }
        let raw: Raw
        do {
            raw = try JSONDecoder().decode(Raw.self, from: data)
        } catch {
            throw DecodeError.invalid
        }
        guard let rawSegments = raw.segments else { throw DecodeError.invalid }
        let segments = rawSegments.compactMap { segment -> TranscriptSegment? in
            let text = (segment.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let start = max(0, segment.start ?? 0)
            let end = max(start, segment.end ?? start)
            return TranscriptSegment(start: start, end: end, text: text)
        }
        .sorted { $0.start < $1.start }
        return Transcript(segments: segments, model: raw.model ?? "")
    }

    /// 앱 저장소에 넣을 때 쓰는 JSON.
    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    /// 앱 저장소에서 꺼낸 JSON.
    public static func stored(_ data: Data) -> Transcript? {
        try? JSONDecoder().decode(Transcript.self, from: data)
    }

    /// 재생 위치에 해당하는 구간 번호. 시작 시각이 `time` 이하인 마지막 구간이다. 첫 구간 전이면 nil.
    public func segmentIndex(at time: TimeInterval) -> Int? {
        var found: Int?
        for (index, segment) in segments.enumerated() {
            if segment.start <= time { found = index } else { break }
        }
        return found
    }

    /// 검색어가 들어 있는 구간 번호들. 대소문자와 앞뒤 공백은 무시한다. 빈 검색어면 빈 배열.
    public func matches(_ query: String) -> [Int] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        return segments.indices.filter { segments[$0].text.range(of: needle, options: [.caseInsensitive]) != nil }
    }

    /// 텍스트로 저장·복사할 때 쓰는 글. 한 줄에 한 구간, 앞에 시각을 붙인다 (예: "[12:40] 이거 시험에 나옵니다.").
    public var plainText: String {
        segments.map { "[\(Self.timestamp($0.start))] \($0.text)" }.joined(separator: "\n")
    }

    /// 1시간 미만은 "m:ss", 넘으면 "h:mm:ss".
    public static func timestamp(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

/// 도우미가 전사하는 동안 쓰는 진행 파일(`{"done": 3, "total": 30}`)을 읽는다.
public enum TranscriptionProgressFile {
    /// 0...1 사이 진행률. 읽을 수 없거나 total이 0 이하면 nil.
    public static func fraction(from data: Data) -> Double? {
        struct Raw: Decodable {
            var done: Double
            var total: Double
        }
        guard let raw = try? JSONDecoder().decode(Raw.self, from: data), raw.total > 0 else { return nil }
        return min(max(raw.done / raw.total, 0), 1)
    }
}
