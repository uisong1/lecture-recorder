import Foundation

/// 웹뷰가 알려 준 미디어 주소 중 본편 영상을 가린다.
public struct LMSVideoCandidate: Equatable, Sendable {
    /// 받을 영상 주소 (`.../screen.mp4`).
    public let url: URL
    /// 영상을 띄운 쪽 페이지 주소. 서버가 Referer로 검사하므로 그대로 보낸다.
    public let referer: URL?
    /// 웹 페이지에서 읽은 강의명. 못 읽었으면 nil.
    public var courseName: String?

    public init(url: URL, referer: URL?, courseName: String? = nil) {
        self.url = url
        self.referer = referer
        self.courseName = courseName
    }
}

public enum LMSVideoDetector {
    /// 본편 영상의 파일 이름. 같은 페이지에 잡히는 `preloader.mp4`, `intro.mp4`는 본편이 아니라서 무시한다.
    public static let lectureFileName = "screen.mp4"

    /// 본편(`screen.mp4`)인지. 쿠키를 붙여 보내므로 https만 받는다.
    public static func isLectureVideo(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.lastPathComponent.lowercased() == lectureFileName
    }

    /// 웹뷰가 보고한 주소 문자열에서 후보를 만든다. 본편이 아니면 nil.
    public static func candidate(urlString: String, refererString: String?, courseName: String? = nil) -> LMSVideoCandidate? {
        guard let url = URL(string: urlString), isLectureVideo(url) else { return nil }
        let name = courseName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return LMSVideoCandidate(
            url: url,
            referer: refererString.flatMap { URL(string: $0) },
            courseName: (name?.isEmpty ?? true) ? nil : name
        )
    }
}

/// LMS 강의명으로 앱의 과목을 추천한다. 틀릴 수 있어서 사용자가 바꿀 수 있게 하는 것이 전제다.
public enum LMSSubjectMatcher {
    /// 공백·기호·대소문자를 없앤 비교용 이름.
    public static func normalize(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// 강의명에 과목 이름이 들어 있거나 그 반대인 과목 중 이름이 가장 긴 것. 없으면 nil.
    public static func bestMatch(courseName: String, among names: [String]) -> String? {
        let course = normalize(courseName)
        guard !course.isEmpty else { return nil }
        var best: (name: String, length: Int)?
        for name in names {
            let candidate = normalize(name)
            guard !candidate.isEmpty, course.contains(candidate) || candidate.contains(course) else { continue }
            if candidate.count > (best?.length ?? 0) { best = (name, candidate.count) }
        }
        return best?.name
    }
}

/// 웹뷰 쿠키 저장소의 쿠키 중 이 주소에 보낼 것만 `Cookie` 헤더 값으로 만든다.
/// 도메인·경로·보안(https만) 규칙을 지켜서 다른 사이트로 로그인 쿠키가 새지 않게 한다.
public struct LMSCookie: Equatable, Sendable {
    public let name: String
    public let value: String
    public let domain: String
    public let path: String
    public let isSecure: Bool
    public let expires: Date?

    public init(name: String, value: String, domain: String, path: String = "/", isSecure: Bool = false, expires: Date? = nil) {
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path
        self.isSecure = isSecure
        self.expires = expires
    }

    func matches(_ url: URL, now: Date) -> Bool {
        if let expires, expires <= now { return false }
        if isSecure, url.scheme?.lowercased() != "https" { return false }
        guard let host = url.host?.lowercased() else { return false }
        let cookieDomain = domain.lowercased()
        let bare = cookieDomain.hasPrefix(".") ? String(cookieDomain.dropFirst()) : cookieDomain
        // 점으로 시작하는 도메인은 하위 도메인까지, 아니면 그 호스트만 맞는다.
        let domainMatches = cookieDomain.hasPrefix(".") ? (host == bare || host.hasSuffix("." + bare)) : host == bare
        guard domainMatches else { return false }
        let requestPath = url.path.isEmpty ? "/" : url.path
        return requestPath == path || requestPath.hasPrefix(path.hasSuffix("/") ? path : path + "/")
    }

    public static func header(for url: URL, cookies: [LMSCookie], now: Date = Date()) -> String? {
        let matching = cookies.filter { $0.matches(url, now: now) }
        // 더 구체적인 경로의 쿠키를 먼저 보낸다.
        .sorted { $0.path.count > $1.path.count }
        guard !matching.isEmpty else { return nil }
        return matching.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }
}
