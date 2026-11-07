import Foundation

/// 수강 중인 Canvas 과목.
public struct CanvasCourse: Equatable, Sendable {
    public let id: Int
    public let name: String

    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

/// 모듈(주차) 안의 강의 항목(LearningX 외부 도구). 영상인지 슬라이드 자료인지는 상세를 읽어야 안다.
public struct CanvasLectureItem: Equatable, Sendable {
    public let moduleName: String
    public let title: String
    /// `/learningx/lti/lecture_attendance/items/view/<id>`의 번호.
    public let itemID: Int
    /// sessionless_launch에 넘길 외부 도구 주소.
    public let launchURL: String

    public init(moduleName: String, title: String, itemID: Int, launchURL: String) {
        self.moduleName = moduleName
        self.title = title
        self.itemID = itemID
        self.launchURL = launchURL
    }
}

/// LTI 실행 양식(자동 제출 form). 브라우저가 하던 제출을 앱이 대신하기 위해 읽는다.
public struct LTIForm: Equatable, Sendable {
    public let action: URL
    /// 양식 값. 서명과 같은 일회용 값이 들어 있어 로그·화면에 남기지 않는다.
    public let fields: [(name: String, value: String)]

    public static func == (lhs: LTIForm, rhs: LTIForm) -> Bool {
        lhs.action == rhs.action && lhs.fields.map { [$0.name, $0.value] } == rhs.fields.map { [$0.name, $0.value] }
    }
}

/// LearningX 항목 상세에서 읽은, commons 콘텐츠를 가리키는 정보.
public struct LearningXContent: Equatable, Sendable {
    /// `commons`면 commons 콘텐츠(영상 또는 슬라이드)다.
    public let contentType: String
    public let contentID: String?

    public var isCommons: Bool { contentType == "commons" && contentID != nil }

    public init(contentType: String, contentID: String?) {
        self.contentType = contentType
        self.contentID = contentID
    }
}

/// commons `content.php` 응답에서 읽은 재생 정보.
public struct CommonsPlayback: Equatable, Sendable {
    /// `video1`은 영상, `sharedocs`는 슬라이드 자료다.
    public let contentType: String
    /// 초. 슬라이드는 0이다.
    public let duration: TimeInterval
    /// 받을 수 있는 mp4 주소들. 영상 서버(commonscdn)를 앞에 둔다.
    public let mp4URLs: [URL]
    /// 응답에 DRM·암호화 표시가 있는가. 있으면 기능을 멈춘다.
    public let hasProtectionMarker: Bool

    /// 받을 수 있는 영상인지.
    public init(contentType: String, duration: TimeInterval, mp4URLs: [URL], hasProtectionMarker: Bool) {
        self.contentType = contentType
        self.duration = duration
        self.mp4URLs = mp4URLs
        self.hasProtectionMarker = hasProtectionMarker
    }

    public var isDownloadableVideo: Bool {
        contentType != "sharedocs" && duration > 0 && !mp4URLs.isEmpty && !hasProtectionMarker
    }
}

public enum CanvasParsingError: Error, Equatable {
    case notJSON
}

public enum CanvasParsing {
    /// `/api/v1/courses` 응답. 이름이 없는 과목은 뺀다.
    public static func courses(from data: Data) throws -> [CanvasCourse] {
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw CanvasParsingError.notJSON
        }
        return array.compactMap { object in
            guard let id = object["id"] as? Int,
                  let name = (object["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty
            else { return nil }
            return CanvasCourse(id: id, name: name)
        }
    }

    /// `/courses/ID/modules?include[]=items` 응답에서 LearningX 강의 항목만 모은다.
    public static func lectureItems(fromModules data: Data) throws -> [CanvasLectureItem] {
        guard let modules = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw CanvasParsingError.notJSON
        }
        var result: [CanvasLectureItem] = []
        for module in modules {
            let moduleName = (module["name"] as? String) ?? ""
            for item in (module["items"] as? [[String: Any]]) ?? [] {
                guard item["type"] as? String == "ExternalTool",
                      let title = item["title"] as? String,
                      let address = (item["external_url"] as? String) ?? (item["html_url"] as? String),
                      let itemID = lectureItemID(in: address)
                else { continue }
                result.append(CanvasLectureItem(moduleName: moduleName, title: title, itemID: itemID, launchURL: address))
            }
        }
        return result
    }

    /// 주소에서 `lecture_attendance/items/view/<번호>`의 번호. 다른 모양이면 nil.
    static func lectureItemID(in address: String) -> Int? {
        guard let range = address.range(of: "/lecture_attendance/items/view/") else { return nil }
        let digits = address[range.upperBound...].prefix { $0.isNumber }
        return Int(digits)
    }

    /// sessionless_launch 응답(JSON)의 실행 주소.
    public static func sessionlessLaunchURL(from data: Data) -> URL? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = object["url"] as? String,
              let url = URL(string: text), url.scheme?.lowercased() == "https"
        else { return nil }
        return url
    }

    /// LTI 자동 제출 양식. 첫 form의 action과 input 값들을 읽는다. 양식이 없으면 nil.
    public static func ltiForm(from html: String, base: URL) -> LTIForm? {
        guard let formMatch = firstMatch(#"<form[^>]*\baction=["']([^"']+)["'][^>]*>(.*?)</form>"#, in: html, options: [.dotMatchesLineSeparators, .caseInsensitive]),
              formMatch.count == 3,
              let action = URL(string: unescape(formMatch[1]), relativeTo: base)?.absoluteURL,
              action.scheme?.lowercased() == "https"
        else { return nil }
        var fields: [(name: String, value: String)] = []
        for input in allMatches(#"<input[^>]*>"#, in: formMatch[2]) {
            guard let name = attribute("name", in: input[0]) else { continue }
            fields.append((unescape(name), unescape(attribute("value", in: input[0]) ?? "")))
        }
        return LTIForm(action: action, fields: fields)
    }

    /// `/learningx/api/v1/courses/ID/attendance_items/항목` 응답.
    public static func learningXContent(from data: Data) throws -> LearningXContent {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CanvasParsingError.notJSON
        }
        let contentData = object["item_content_data"] as? [String: Any]
        let contentID = (contentData?["content_id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return LearningXContent(contentType: (object["item_content_type"] as? String) ?? "", contentID: contentID)
    }

    /// commons `content.php` XML에서 재생 정보를 읽는다.
    public static func playback(fromContentXML xml: String) -> CommonsPlayback {
        let contentType = firstMatch(#"<content_type>\s*(?:<!\[CDATA\[)?([^<\]]*)"#, in: xml)?[1].trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let durationText = firstMatch(#"<content_duration>\s*(?:<!\[CDATA\[)?([^<\]]*)"#, in: xml)?[1].trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var urls: [URL] = []
        for match in allMatches(#"<media_uri[^>]*>\s*(?:<!\[CDATA\[)?(https://[^<\]\s]+)"#, in: xml) {
            guard let url = URL(string: unescape(match[1])), url.path.lowercased().hasSuffix(".mp4"), !urls.contains(url) else { continue }
            urls.append(url)
        }
        // 영상 서버(commonscdn)를 앞에 둔다. commons.ssu.ac.kr의 pseudo 경로는 503이 났다.
        urls.sort { ($0.host ?? "").contains("commonscdn") && !($1.host ?? "").contains("commonscdn") }
        let lowered = xml.lowercased()
        let hasProtection = ["<drm", "widevine", "fairplay", "playready", "<license_url", "encryption"].contains { lowered.contains($0) }
        return CommonsPlayback(
            contentType: contentType,
            duration: TimeInterval(durationText) ?? 0,
            mp4URLs: urls,
            hasProtectionMarker: hasProtection
        )
    }

    // MARK: 도우미

    private static func firstMatch(_ pattern: String, in text: String, options: NSRegularExpression.Options = []) -> [String]? {
        allMatches(pattern, in: text, options: options).first
    }

    private static func allMatches(_ pattern: String, in text: String, options: NSRegularExpression.Options = []) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let whole = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: whole).map { match in
            (0..<match.numberOfRanges).map { index in
                Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
            }
        }
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        firstMatch(#"\b"# + name + #"\s*=\s*(?:"([^"]*)"|'([^']*)')"#, in: tag, options: .caseInsensitive).map { $0[1].isEmpty ? $0[2] : $0[1] }
    }

    private static func unescape(_ text: String) -> String {
        text.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}
