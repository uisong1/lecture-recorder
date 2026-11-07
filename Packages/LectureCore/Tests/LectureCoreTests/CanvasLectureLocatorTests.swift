import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import LectureCore

/// 주소에 들어 있는 글자로 응답을 고르는 가짜 클라이언트. 보낸 요청을 순서대로 모은다.
final class FakeCanvasClient: CanvasHTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [URLRequest] = []
    var cookies: [String: String] = [:]
    /// (주소에 들어 있는 글자, 응답). 위에서부터 처음 맞는 것을 쓴다.
    var routes: [(match: String, status: Int, body: String)] = []

    var requests: [URLRequest] { lock.withLock { _requests } }

    func send(_ request: URLRequest) async throws -> CanvasHTTPResponse {
        lock.withLock { _requests.append(request) }
        let url = request.url ?? URL(string: "https://invalid.example")!
        let route = routes.first { url.absoluteString.contains($0.match) }
        return CanvasHTTPResponse(data: Data((route?.body ?? "").utf8), statusCode: route?.status ?? 404, url: url)
    }

    func cookieValue(named name: String, for url: URL) async -> String? { cookies[name] }

    func request(containing text: String) -> URLRequest? {
        requests.first { ($0.url?.absoluteString ?? "").contains(text) }
    }
}

@Suite struct CanvasLectureLocatorTests {
    let item = CanvasLectureItem(moduleName: "9주차", title: "2_3_calling_convention_1", itemID: 981471,
                                 launchURL: "https://canvas.ssu.ac.kr/learningx/lti/lecture_attendance/items/view/981471")

    func makeClient(contentXML: String = CanvasParsingTests.videoXML, itemJSON: String? = nil, form: Bool = true, cookie: Bool = true) -> FakeCanvasClient {
        let client = FakeCanvasClient()
        if cookie { client.cookies["xn_api_token"] = "LEARNINGX-SECRET" }
        let launchPage = form
            ? #"<form action="https://canvas.ssu.ac.kr/learningx/lti/lecture_attendance/items/view/981471" method="post"><input type="hidden" name="oauth_signature" value="a+b/c="><input type="hidden" name="x" value="y"></form>"#
            : "<html>로그인이 필요합니다</html>"
        client.routes = [
            ("/api/v1/courses?enrollment_state", 200, #"[{"id":48761,"name":"컴퓨터구조 (2150246401)"}]"#),
            ("/modules?include", 200, #"[{"name":"9주차","items":[{"title":"2_3_calling_convention_1","type":"ExternalTool","external_url":"https://canvas.ssu.ac.kr/learningx/lti/lecture_attendance/items/view/981471"}]}]"#),
            ("sessionless_launch?url=", 200, #"{"url":"https://canvas.ssu.ac.kr/courses/48761/external_tools/sessionless_launch?verifier=v"}"#),
            ("sessionless_launch?verifier", 200, launchPage),
            ("/lecture_attendance/items/view/981471", 200, "<html>LearningX</html>"),
            ("/attendance_items/981471", 200, itemJSON ?? #"{"item_content_type":"commons","item_content_data":{"content_id":"6ae1ae10f2791"}}"#),
            ("content.php", 200, contentXML),
        ]
        return client
    }

    func locator(_ client: FakeCanvasClient) -> CanvasLectureLocator {
        CanvasLectureLocator(client: client, token: "CANVAS-SECRET")
    }

    @Test func 수강_과목과_강의_항목을_토큰으로_읽는다() async throws {
        let client = makeClient()
        let courses = try await locator(client).courses()
        #expect(courses == [CanvasCourse(id: 48761, name: "컴퓨터구조 (2150246401)")])
        let items = try await locator(client).lectureItems(courseID: 48761)
        #expect(items.map(\.itemID) == [981471])
        #expect(client.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer CANVAS-SECRET" })
    }

    @Test func 영상_재생_정보까지_순서대로_찾는다() async throws {
        let client = makeClient()
        let playback = try await locator(client).playback(courseID: 48761, item: item)
        #expect(playback.isDownloadableVideo)
        #expect(playback.mp4URLs.first?.host == "ssuin-object.commonscdn.com")

        let order = client.requests.compactMap { $0.url?.absoluteString }
        func index(_ text: String) -> Int? { order.firstIndex { $0.contains(text) } }
        let launch = try #require(index("sessionless_launch?url="))
        let page = try #require(index("sessionless_launch?verifier"))
        let post = try #require(client.requests.firstIndex { $0.httpMethod == "POST" })
        let detail = try #require(index("/attendance_items/981471"))
        let info = try #require(index("content.php"))
        #expect(launch < page && page < post && post < detail && detail < info)
    }

    @Test func 토큰은_Canvas_API에만_LearningX_세션은_LearningX_API에만_보낸다() async throws {
        let client = makeClient()
        _ = try await locator(client).playback(courseID: 48761, item: item)
        #expect(client.request(containing: "sessionless_launch?url=")?.value(forHTTPHeaderField: "Authorization") == "Bearer CANVAS-SECRET")
        #expect(client.request(containing: "/attendance_items/981471")?.value(forHTTPHeaderField: "Authorization") == "Bearer LEARNINGX-SECRET")
        // 양식 제출과 commons 요청에는 토큰을 보내지 않는다.
        for request in client.requests where request.httpMethod == "POST" || (request.url?.host ?? "") == "commons.ssu.ac.kr" {
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        }
    }

    @Test func 양식은_브라우저처럼_제출하고_특수문자를_인코딩한다() async throws {
        let client = makeClient()
        _ = try await locator(client).playback(courseID: 48761, item: item)
        let post = try #require(client.requests.first { $0.httpMethod == "POST" })
        #expect(String(decoding: post.httpBody ?? Data(), as: UTF8.self) == "oauth_signature=a%2Bb%2Fc%3D&x=y")
        #expect(post.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        #expect(post.value(forHTTPHeaderField: "Origin") == "https://canvas.ssu.ac.kr")
        #expect(post.value(forHTTPHeaderField: "Referer") == "https://canvas.ssu.ac.kr")
        #expect((post.value(forHTTPHeaderField: "User-Agent") ?? "").hasPrefix("Mozilla/5.0"))
    }

    @Test func commons_요청에는_재생_화면을_Referer로_보낸다() async throws {
        let client = makeClient()
        _ = try await locator(client).playback(courseID: 48761, item: item)
        #expect(client.request(containing: "content.php")?.value(forHTTPHeaderField: "Referer") == "https://commons.ssu.ac.kr/em/6ae1ae10f2791")
    }

    @Test func 슬라이드_자료는_영상이_아니다() async throws {
        let slides = "<content><content_playing_info><content_type>sharedocs</content_type><content_duration>0</content_duration></content_playing_info></content>"
        await #expect(throws: CanvasError.notVideo) {
            _ = try await locator(makeClient(contentXML: slides)).playback(courseID: 48761, item: item)
        }
    }

    @Test func commons가_아닌_항목은_영상이_아니다() async throws {
        let client = makeClient(itemJSON: #"{"item_content_type":"pdf"}"#)
        await #expect(throws: CanvasError.notVideo) {
            _ = try await locator(client).playback(courseID: 48761, item: item)
        }
        #expect(client.request(containing: "content.php") == nil)
    }

    @Test func 보호_표시가_있으면_멈춘다() async throws {
        let xml = CanvasParsingTests.videoXML.replacingOccurrences(of: "<media type=\"default\">", with: "<media type=\"default\"><drm type=\"widevine\"/>")
        await #expect(throws: CanvasError.protectedContent) {
            _ = try await locator(makeClient(contentXML: xml)).playback(courseID: 48761, item: item)
        }
    }

    @Test func 로그인_양식이_없거나_세션_쿠키가_없으면_세션을_얻지_못한_것이다() async throws {
        await #expect(throws: CanvasError.sessionUnavailable) {
            _ = try await locator(makeClient(form: false)).playback(courseID: 48761, item: item)
        }
        await #expect(throws: CanvasError.sessionUnavailable) {
            _ = try await locator(makeClient(cookie: false)).playback(courseID: 48761, item: item)
        }
    }

    @Test func 토큰이_틀리면_알려_준다() async throws {
        let client = FakeCanvasClient()
        client.routes = [("/api/v1/courses", 401, "{}")]
        await #expect(throws: CanvasError.unauthorized) { _ = try await locator(client).courses() }
        client.routes = [("/api/v1/courses", 500, "")]
        await #expect(throws: CanvasError.httpStatus(500)) { _ = try await locator(client).courses() }
    }

    @Test func 오류_문구에_토큰이_들어가지_않는다() {
        let all: [CanvasError] = [.noToken, .unauthorized, .httpStatus(500), .invalidResponse, .notVideo, .protectedContent, .sessionUnavailable]
        for error in all {
            #expect(!(error.errorDescription ?? "").contains("SECRET"))
            #expect(!(error.errorDescription ?? "").isEmpty)
        }
    }

    @Test func 인코딩은_영문_숫자와_안전한_기호만_남긴다() {
        #expect(CanvasLectureLocator.percentEncode("a b+c&d=e/f") == "a%20b%2Bc%26d%3De%2Ff")
        #expect(CanvasLectureLocator.percentEncode("A-z_0.9~") == "A-z_0.9~")
    }
}
