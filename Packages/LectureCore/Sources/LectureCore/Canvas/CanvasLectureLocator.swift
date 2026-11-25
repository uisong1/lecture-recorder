import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Canvas·LearningX·commons로 보내는 요청과 응답. 테스트에서는 가짜 구현을 쓴다.
public struct CanvasHTTPResponse: Sendable {
    public let data: Data
    public let statusCode: Int
    /// 리다이렉트를 따라간 뒤의 주소.
    public let url: URL
    /// `Link` 응답 헤더(다음 쪽 주소). 없으면 nil.
    public let linkHeader: String?

    public init(data: Data, statusCode: Int, url: URL, linkHeader: String? = nil) {
        self.data = data
        self.statusCode = statusCode
        self.url = url
        self.linkHeader = linkHeader
    }
}

public protocol CanvasHTTPClient: Sendable {
    /// 요청을 보낸다. 쿠키는 구현이 이 클라이언트 안에서만 들고 있고 디스크에 남기지 않는다.
    func send(_ request: URLRequest) async throws -> CanvasHTTPResponse
    /// 이 클라이언트가 받은 쿠키 값. 없으면 nil.
    func cookieValue(named name: String, for url: URL) async -> String?
}

/// Canvas 개인 액세스 토큰 보관소. 토큰은 Keychain에만 둔다.
public protocol CanvasTokenStoring: Sendable {
    func loadToken() throws -> String?
    func saveToken(_ token: String) throws
    func deleteToken() throws
}

public enum CanvasError: Error, Equatable, LocalizedError {
    case noToken
    /// 토큰이 틀렸거나 만료됐다.
    case unauthorized
    case httpStatus(Int)
    case invalidResponse
    /// 항목이 영상이 아니다(슬라이드 자료 등).
    case notVideo
    /// 응답에 DRM·암호화 표시가 있다. 우회하지 않고 멈춘다.
    case protectedContent
    /// LearningX로 넘어가는 양식이나 세션을 얻지 못했다.
    case sessionUnavailable

    public var errorDescription: String? {
        switch self {
        case .noToken: "Canvas 토큰이 없어요. 설정에서 토큰을 넣어 주세요."
        case .unauthorized: "Canvas 토큰이 틀렸거나 만료됐어요. 설정에서 새 토큰을 넣어 주세요."
        case .httpStatus(let code): "LMS가 요청을 받아주지 않았어요 (HTTP \(code))."
        case .invalidResponse: "LMS 응답을 읽지 못했어요. 화면 구조가 바뀌었을 수 있어요."
        case .notVideo: "이 항목은 영상이 아니에요."
        case .protectedContent: "이 영상에 암호화(DRM) 표시가 있어요. 우회하지 않고 멈췄어요."
        case .sessionUnavailable: "LearningX에 접속하지 못했어요. 잠시 뒤 다시 시도해 주세요."
        }
    }
}

/// Canvas 개인 토큰으로 수강 과목, 주차별 강의 항목, 영상 주소를 찾는다. 읽기만 하고 영상은 받지 않는다.
/// 토큰·쿠키·양식 값은 로그나 오류 문구에 넣지 않는다.
public struct CanvasLectureLocator: Sendable {
    public static let browserUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    static let commonsHost = "https://commons.ssu.ac.kr"

    let client: any CanvasHTTPClient
    let baseURL: URL
    let token: String

    public init(client: any CanvasHTTPClient, token: String, baseURL: URL = URL(string: "https://canvas.ssu.ac.kr")!) {
        self.client = client
        self.token = token
        self.baseURL = baseURL
    }

    /// 수강 중인 과목.
    public func courses() async throws -> [CanvasCourse] {
        let data = try await get("/api/v1/courses?enrollment_state=active&per_page=100", bearer: token)
        return try CanvasParsing.courses(from: data)
    }

    /// 과목의 주차별 강의 항목(영상인지 슬라이드인지는 아직 모른다).
    public func lectureItems(courseID: Int) async throws -> [CanvasLectureItem] {
        let data = try await get("/api/v1/courses/\(courseID)/modules?include%5B%5D=items&per_page=100", bearer: token)
        return try CanvasParsing.lectureItems(fromModules: data)
    }

    /// 항목의 영상 재생 정보. 영상이 아니면 `notVideo`, 보호 표시가 있으면 `protectedContent`.
    public func playback(courseID: Int, item: CanvasLectureItem) async throws -> CommonsPlayback {
        let xml = try await commonsContentXML(courseID: courseID, item: item)
        let playback = CanvasParsing.playback(fromContentXML: xml)
        if playback.hasProtectionMarker { throw CanvasError.protectedContent }
        guard playback.isDownloadableVideo else { throw CanvasError.notVideo }
        return playback
    }

    /// 슬라이드·문서 항목에서 받을 수 있는 PDF 주소와, 응답 구조 요약(주소·토큰 없이 태그 이름과 확장자만).
    /// 보호 표시가 있으면 `protectedContent`.
    public func documents(courseID: Int, item: CanvasLectureItem) async throws -> CommonsDocuments {
        let xml = try await commonsContentXML(courseID: courseID, item: item)
        if CanvasParsing.playback(fromContentXML: xml).hasProtectionMarker { throw CanvasError.protectedContent }
        return CanvasParsing.documents(fromContentXML: xml)
    }

    /// LearningX 항목의 commons `content.php` XML. commons 콘텐츠가 아니면 `notVideo`.
    private func commonsContentXML(courseID: Int, item: CanvasLectureItem) async throws -> String {
        // 1. 토큰으로 LearningX 실행 주소를 받는다(공식 API).
        let launchQuery = Self.percentEncode(item.launchURL)
        let launchData = try await get("/api/v1/courses/\(courseID)/external_tools/sessionless_launch?url=\(launchQuery)", bearer: token)
        guard let launchURL = CanvasParsing.sessionlessLaunchURL(from: launchData) else { throw CanvasError.invalidResponse }

        // 2. 실행 페이지가 돌려주는 자동 제출 양식을 브라우저처럼 제출한다.
        let page = try await send(Self.browserRequest(url: launchURL, referer: baseURL))
        guard let form = CanvasParsing.ltiForm(from: String(decoding: page.data, as: UTF8.self), base: launchURL) else {
            throw CanvasError.sessionUnavailable
        }
        var post = Self.browserRequest(url: form.action, referer: baseURL)
        post.httpMethod = "POST"
        post.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        post.setValue(Self.origin(of: baseURL), forHTTPHeaderField: "Origin")
        post.httpBody = Data(form.fields.map { "\(Self.percentEncode($0.name))=\(Self.percentEncode($0.value))" }.joined(separator: "&").utf8)
        _ = try await send(post)
        guard let learningXToken = await client.cookieValue(named: "xn_api_token", for: baseURL) else {
            throw CanvasError.sessionUnavailable
        }

        // 3. 항목 상세에서 commons 콘텐츠 번호를 읽는다.
        let detail = try await get("/learningx/api/v1/courses/\(courseID)/attendance_items/\(item.itemID)", bearer: learningXToken)
        let content = try CanvasParsing.learningXContent(from: detail)
        guard content.isCommons, let contentID = content.contentID else { throw CanvasError.notVideo }

        // 4. commons 재생 정보(XML)를 읽는다.
        let infoURL = try Self.url("\(Self.commonsHost)/viewer/ssplayer/uniplayer_support/content.php?content_id=\(Self.percentEncode(contentID))")
        let info = try await send(Self.browserRequest(url: infoURL, referer: try Self.url("\(Self.commonsHost)/em/\(Self.percentEncode(contentID))")))
        return String(decoding: info.data, as: UTF8.self)
    }

    // MARK: 강의자료(PDF)

    /// 과목의 PDF 강의자료 목록(읽기만 한다). 파일 메뉴가 열려 있으면 과목 파일에서, 학교가 막아 뒀으면
    /// 주차별 모듈의 파일 항목에서 찾는다. 잠겨서 받을 수 없는 파일은 `lockedCount`로 센다.
    public func pdfFiles(courseID: Int) async throws -> CanvasFileList {
        var result = CanvasFileList()
        var tabNote = "파일 메뉴 막힘"
        var tabOpened = false
        do {
            var next: String? = "/api/v1/courses/\(courseID)/files?content_types%5B%5D=application%2Fpdf&per_page=100"
            var pages = 0
            while let path = next, pages < 20 {
                let response = try await getResponse(path, bearer: token)
                result.merge(try CanvasParsing.files(from: response.data))
                next = CanvasParsing.nextPage(fromLinkHeader: response.linkHeader).flatMap { relativePath(of: $0) }
                pages += 1
            }
            tabOpened = true
            tabNote = "파일 메뉴 PDF \(result.files.count + result.lockedCount)개"
            // 파일 메뉴에서 하나라도 찾았으면 그대로 쓴다. 비어 있으면 모듈의 파일 항목도 본다.
            if !result.files.isEmpty || result.lockedCount > 0 {
                result.note = tabNote
                return result
            }
        } catch CanvasError.unauthorized, CanvasError.httpStatus(403), CanvasError.httpStatus(404) {
            // 이 과목은 파일 메뉴가 닫혀 있다. 모듈에 올린 파일 항목으로 대신한다.
        }
        let modules: Data
        do {
            modules = try await get("/api/v1/courses/\(courseID)/modules?include%5B%5D=items&per_page=100", bearer: token)
        } catch where tabOpened {
            // 파일 메뉴는 열렸는데 비어 있고 모듈도 못 읽었다. 오류로 끝내지 않고 못 찾았다고 알린다.
            result.note = "\(tabNote), 모듈 읽기 실패"
            return result
        }
        let fileIDs = try CanvasParsing.fileItemIDs(fromModules: modules)
        for fileID in fileIDs {
            // 파일 하나가 안 열려도(삭제·권한) 나머지는 계속 찾는다.
            guard let data = try? await get("/api/v1/courses/\(courseID)/files/\(fileID)", bearer: token) else {
                result.failedLookups += 1
                continue
            }
            result.merge(try CanvasParsing.files(from: data))
        }
        // 과제 설명에 붙은 파일 링크도 본다(파일 메뉴가 막힌 과목은 보통 여기로 올라온다).
        let assignmentIDs = CanvasParsing.assignmentIDs(fromModules: modules)
        var assignmentFiles = 0
        for assignmentID in assignmentIDs.prefix(40) {
            guard let data = try? await get("/api/v1/courses/\(courseID)/assignments/\(assignmentID)", bearer: token) else { continue }
            for fileID in CanvasParsing.fileIDs(inHTML: CanvasParsing.assignmentDescription(from: data)) where !fileIDs.contains(fileID) {
                guard let fileData = try? await get("/api/v1/courses/\(courseID)/files/\(fileID)", bearer: token) else { continue }
                let found = (try? CanvasParsing.files(from: fileData)) ?? CanvasFileList()
                assignmentFiles += found.files.count
                result.merge(found)
            }
        }
        let kinds = CanvasParsing.moduleItemTypeCounts(from: modules).sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
        result.note = "\(tabNote), 모듈 파일 항목 \(fileIDs.count)개, 과제 첨부 PDF \(assignmentFiles)개, 모듈 항목 종류: \(kinds.isEmpty ? "없음" : kinds)"
        return result
    }

    /// PDF 파일 하나를 받는다. 실제 PDF가 아니면(로그인 안내 페이지 등) `invalidResponse`.
    public func download(_ file: CanvasFile) async throws -> Data {
        var request = URLRequest(url: file.downloadURL)
        if file.downloadURL.host == baseURL.host {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            // 토큰은 Canvas에만 보낸다. 다른 서버(commons)에는 Referer만 붙인다.
            request.setValue(Self.commonsHost + "/", forHTTPHeaderField: "Referer")
        }
        request.setValue(Self.browserUserAgent, forHTTPHeaderField: "User-Agent")
        let data = try await send(request).data
        guard data.starts(with: Data("%PDF".utf8)) else { throw CanvasError.invalidResponse }
        return data
    }

    /// 다음 쪽 주소를 baseURL 기준 경로로 바꾼다. 다른 호스트면 따라가지 않는다.
    private func relativePath(of url: URL) -> String? {
        guard url.host == baseURL.host else { return nil }
        let query = url.query.map { "?\($0)" } ?? ""
        return url.path + query
    }

    // MARK: 도우미

    private func get(_ path: String, bearer: String) async throws -> Data {
        try await getResponse(path, bearer: bearer).data
    }

    private func getResponse(_ path: String, bearer: String) async throws -> CanvasHTTPResponse {
        var request = URLRequest(url: try Self.url(baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path))
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.browserUserAgent, forHTTPHeaderField: "User-Agent")
        return try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> CanvasHTTPResponse {
        let response = try await client.send(request)
        switch response.statusCode {
        case 200..<300: return response
        case 401: throw CanvasError.unauthorized
        default: throw CanvasError.httpStatus(response.statusCode)
        }
    }

    static func browserRequest(url: URL, referer: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        return request
    }

    static func url(_ text: String) throws -> URL {
        guard let url = URL(string: text) else { throw CanvasError.invalidResponse }
        return url
    }

    static func origin(of url: URL) -> String {
        "\(url.scheme ?? "https")://\(url.host ?? "")"
    }

    /// 쿼리·양식에 넣을 값을 인코딩한다. 영문·숫자와 `-._~`만 그대로 둔다(`+`, `&`, `=`도 인코딩).
    static func percentEncode(_ text: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }
}
