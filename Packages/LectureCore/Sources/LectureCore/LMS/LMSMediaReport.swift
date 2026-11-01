import Foundation

/// 웹뷰의 감시 스크립트가 보낸 한 건의 보고. 영상 후보를 만들고, 감지가 안 될 때 원인을 볼 수 있게 한 줄 요약도 만든다.
public struct LMSMediaReport: Equatable, Sendable {
    public enum Kind: String, Sendable {
        /// 미디어로 보이는 주소를 봤다 (`<video>`, `fetch`, `XHR` 등).
        case media
        /// 스크립트가 어떤 프레임에서 시작됐다 (영상 플레이어가 든 iframe에 닿는지 확인용).
        case frame
    }

    public let kind: Kind
    public let url: String
    /// 보고한 프레임의 주소. 서버가 Referer로 검사하므로 영상 받을 때 그대로 쓴다.
    public let page: String?
    /// 어떻게 봤는지 (`element`, `fetch`, `xhr`, `event`, `src-setter`).
    public let via: String?

    public init?(body: [String: Any]) {
        guard let kindText = body["kind"] as? String, let kind = Kind(rawValue: kindText),
              let url = body["url"] as? String, !url.isEmpty else { return nil }
        self.kind = kind
        self.url = url
        page = body["page"] as? String
        via = body["via"] as? String
    }

    /// 본편(`screen.mp4`)이면 받을 후보. 아니면 nil.
    public func candidate(courseName: String?) -> LMSVideoCandidate? {
        guard kind == .media else { return nil }
        return LMSVideoDetector.candidate(urlString: url, refererString: page, courseName: courseName)
    }

    /// 감지 정보에 보일 한 줄. 쿼리와 조각(토큰이 들어 있을 수 있다)은 뺀다.
    public var summary: String {
        let label = kind == .media ? "미디어" : "프레임"
        let how = via.map { " (\($0))" } ?? ""
        if url.hasPrefix("blob:") { return "\(label): blob 주소 — 스트리밍 재생일 수 있음\(how)" }
        if url.hasPrefix("data:") { return "\(label): data 주소\(how)" }
        guard let parsed = URL(string: url), let host = parsed.host else { return "\(label): \(String(url.prefix(60)))\(how)" }
        let text = host + parsed.path
        let shortened = text.count > 90 ? "…" + text.suffix(89) : text
        let tag = kind == .media && LMSVideoDetector.isLectureVideo(parsed) ? " ★본편" : ""
        return "\(label): \(shortened)\(tag)\(how)"
    }
}

/// 감지 정보 목록. 같은 줄은 한 번만 두고 오래된 것부터 버린다.
public struct LMSDiagnostics: Equatable, Sendable {
    public static let capacity = 14
    public private(set) var lines: [String] = []

    public init() {}

    public mutating func record(_ line: String) {
        guard !lines.contains(line) else { return }
        lines.append(line)
        if lines.count > Self.capacity { lines.removeFirst(lines.count - Self.capacity) }
    }

    public mutating func clear() { lines = [] }
}
