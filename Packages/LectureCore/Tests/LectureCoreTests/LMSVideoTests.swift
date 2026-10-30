import Foundation
import Testing
@testable import LectureCore

/// 테스트용 mp4 바이트. `ftyp` 상자 뒤에 `moov`(안에 `moovContent`)와 `mdat`를 붙인다.
func fakeMP4(moovContent: String = "trak") -> Data {
    func box(_ type: String, _ body: Data) -> Data {
        var size = UInt32(8 + body.count).bigEndian
        return Data(bytes: &size, count: 4) + Data(type.utf8) + body
    }
    return box("ftyp", Data("isom".utf8) + Data(count: 4))
        + box("moov", Data(moovContent.utf8))
        + box("mdat", Data(count: 32))
}

@Suite struct LMSVideoDetectorTests {
    @Test func screen_mp4만_본편으로_본다() {
        #expect(LMSVideoDetector.candidate(urlString: "https://cdn.example.ac.kr/a/b/screen.mp4", refererString: nil) != nil)
        #expect(LMSVideoDetector.candidate(urlString: "https://cdn.example.ac.kr/a/b/preloader.mp4", refererString: nil) == nil)
        #expect(LMSVideoDetector.candidate(urlString: "https://cdn.example.ac.kr/a/b/intro.mp4", refererString: nil) == nil)
        #expect(LMSVideoDetector.candidate(urlString: "https://cdn.example.ac.kr/a/b/SCREEN.MP4?token=1", refererString: nil) != nil)
    }

    @Test func https가_아니면_쿠키를_보내지_않도록_후보로_보지_않는다() {
        #expect(LMSVideoDetector.candidate(urlString: "http://cdn.example.ac.kr/screen.mp4", refererString: nil) == nil)
        #expect(LMSVideoDetector.candidate(urlString: "not a url", refererString: nil) == nil)
    }

    @Test func 후보에_referer와_강의명이_담긴다() throws {
        let candidate = try #require(LMSVideoDetector.candidate(
            urlString: "https://cdn.example.ac.kr/screen.mp4",
            refererString: "https://lms.example.ac.kr/viewer?id=1",
            courseName: "  운영체제  "
        ))
        #expect(candidate.referer?.absoluteString == "https://lms.example.ac.kr/viewer?id=1")
        #expect(candidate.courseName == "운영체제")
        #expect(LMSVideoDetector.candidate(urlString: "https://a.kr/screen.mp4", refererString: nil, courseName: "  ")?.courseName == nil)
    }
}

@Suite struct LMSSubjectMatcherTests {
    let names = ["운영체제", "자료구조", "자료구조및실습"]

    @Test func 강의명에_과목_이름이_들어_있으면_추천한다() {
        #expect(LMSSubjectMatcher.bestMatch(courseName: "운영체제 (01분반)", among: names) == "운영체제")
        #expect(LMSSubjectMatcher.bestMatch(courseName: "[2026-2] 자료 구조", among: names) == "자료구조")
    }

    @Test func 이름이_긴_과목을_먼저_고른다() {
        #expect(LMSSubjectMatcher.bestMatch(courseName: "자료구조 및 실습", among: names) == "자료구조및실습")
    }

    @Test func 맞는_과목이_없거나_강의명이_비면_nil() {
        #expect(LMSSubjectMatcher.bestMatch(courseName: "컴퓨터구조", among: names) == nil)
        #expect(LMSSubjectMatcher.bestMatch(courseName: "  ", among: names) == nil)
        #expect(LMSSubjectMatcher.bestMatch(courseName: "운영체제", among: []) == nil)
    }
}

@Suite struct LMSCookieTests {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let video = URL(string: "https://cdn.example.ac.kr/lecture/screen.mp4")!

    @Test func 도메인과_경로가_맞는_쿠키만_보낸다() {
        let cookies = [
            LMSCookie(name: "a", value: "1", domain: ".example.ac.kr"),
            LMSCookie(name: "b", value: "2", domain: "cdn.example.ac.kr", path: "/lecture"),
            LMSCookie(name: "other", value: "x", domain: "evil.com"),
            LMSCookie(name: "host", value: "y", domain: "lms.example.ac.kr"),
            LMSCookie(name: "path", value: "z", domain: ".example.ac.kr", path: "/admin"),
        ]
        let header = LMSCookie.header(for: video, cookies: cookies, now: now)
        #expect(header == "b=2; a=1")
    }

    @Test func 만료된_쿠키와_보안_쿠키는_조건에_따라_뺀다() {
        let cookies = [
            LMSCookie(name: "old", value: "1", domain: ".example.ac.kr", expires: now.addingTimeInterval(-1)),
            LMSCookie(name: "live", value: "2", domain: ".example.ac.kr", isSecure: true, expires: now.addingTimeInterval(60)),
        ]
        #expect(LMSCookie.header(for: video, cookies: cookies, now: now) == "live=2")
        #expect(LMSCookie.header(for: URL(string: "http://cdn.example.ac.kr/screen.mp4")!, cookies: cookies, now: now) == nil)
    }

    @Test func 도메인이_다른_사이트에는_보내지_않는다() {
        let cookies = [LMSCookie(name: "a", value: "1", domain: ".example.ac.kr")]
        #expect(LMSCookie.header(for: URL(string: "https://notexample.ac.kr/screen.mp4")!, cookies: cookies, now: now) == nil)
    }
}

@Suite struct MediaEncryptionTests {
    func write(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).mp4")
        try data.write(to: url)
        return url
    }

    @Test func 보호_표시가_없는_mp4는_암호화로_보지_않는다() throws {
        let url = try write(fakeMP4())
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(MediaFileValidator.hasFtypBox(at: url))
        #expect(!MediaFileValidator.isEncrypted(at: url))
    }

    @Test func moov_안에_보호_표시가_있으면_암호화로_본다() throws {
        for marker in ["sinf", "encv", "enca", "cenc"] {
            let url = try write(fakeMP4(moovContent: "trak" + marker))
            defer { try? FileManager.default.removeItem(at: url) }
            #expect(MediaFileValidator.isEncrypted(at: url), "\(marker)")
        }
    }

    @Test func 상자가_깨졌으면_암호화로_보지_않는다() throws {
        let url = try write(Data("ftypjunk".utf8))
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(!MediaFileValidator.isEncrypted(at: url))
    }

    @Test func html과_스트리밍_목록을_알아본다() {
        #expect(MediaFileValidator.looksLikeHTML(Data("<!DOCTYPE html><html>".utf8)))
        #expect(!MediaFileValidator.looksLikeHTML(fakeMP4()))
        #expect(MediaFileValidator.looksLikeStreamingManifest(Data("#EXTM3U\n#EXT-X".utf8)))
        #expect(MediaFileValidator.looksLikeStreamingManifest(Data("<MPD xmlns=...".utf8)))
    }
}

/// 시도마다 정해 둔 결과를 내는 가짜 다운로더.
final class FakeLMSDownloader: LMSDownloading, @unchecked Sendable {
    enum Outcome {
        case data(Data, lastModified: Date? = nil)
        case failure(LMSDownloadError)
        case other(any Error)
    }

    private let lock = NSLock()
    private var outcomes: [Outcome]
    private var _requests: [LMSDownloadRequest] = []
    /// 파일을 받을 때마다 부르는 동작 (가짜 파일 시스템에 알리는 데 쓴다).
    var onWrite: (@Sendable (URL, Data) -> Void)?

    init(_ outcomes: [Outcome]) { self.outcomes = outcomes }

    var requests: [LMSDownloadRequest] { lock.withLock { _requests } }

    func download(_ request: LMSDownloadRequest, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> LMSDownloadResult {
        let outcome = lock.withLock { () -> Outcome in
            _requests.append(request)
            return outcomes.count > 1 ? outcomes.removeFirst() : outcomes[0]
        }
        switch outcome {
        case .data(let data, let lastModified):
            try data.write(to: destination)
            onWrite?(destination, data)
            progress(1)
            return LMSDownloadResult(lastModified: lastModified)
        case .failure(let error): throw error
        case .other(let error): throw error
        }
    }
}

struct Timeout: Error {}

@Suite struct LMSVideoFetcherTests {
    let request = LMSDownloadRequest(
        url: URL(string: "https://cdn.example.ac.kr/screen.mp4")!,
        referer: URL(string: "https://lms.example.ac.kr/viewer"),
        cookieHeader: "a=1"
    )
    let destination = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).mp4")

    func fetcher(_ downloader: FakeLMSDownloader, playable: Bool = true) -> LMSVideoFetcher {
        LMSVideoFetcher(downloader: downloader, sleep: { _ in }, isPlayable: { _ in playable })
    }

    @Test func 정상_mp4는_한_번에_받는다() async throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let downloader = FakeLMSDownloader([.data(fakeMP4(), lastModified: date)])
        defer { try? FileManager.default.removeItem(at: destination) }

        let result = try await fetcher(downloader).fetch(request, to: destination)

        #expect(result.lastModified == date)
        #expect(downloader.requests == [request])
        #expect(FileManager.default.fileExists(atPath: destination.path))
    }

    @Test func 일부만_받았거나_서버_오류면_다시_받는다() async throws {
        let downloader = FakeLMSDownloader([.failure(.httpStatus(206)), .failure(.incomplete(expected: 10, actual: 4)), .data(fakeMP4())])
        defer { try? FileManager.default.removeItem(at: destination) }

        _ = try await fetcher(downloader).fetch(request, to: destination)

        #expect(downloader.requests.count == 3)
    }

    @Test func 정상이_아닌_파일이_계속_오면_세_번_시도하고_실패하며_파일을_남기지_않는다() async throws {
        let downloader = FakeLMSDownloader([.data(Data("garbage bytes here".utf8))])

        await #expect(throws: LMSFetchError.invalidFile) {
            _ = try await fetcher(downloader).fetch(request, to: destination)
        }
        #expect(downloader.requests.count == 3)
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test func 재생_길이를_읽지_못하면_다시_받는다() async throws {
        let downloader = FakeLMSDownloader([.data(fakeMP4())])

        await #expect(throws: LMSFetchError.invalidFile) {
            _ = try await fetcher(downloader, playable: false).fetch(request, to: destination)
        }
        #expect(downloader.requests.count == 3)
    }

    @Test func 로그인이_만료되면_다시_받지_않고_알린다() async throws {
        for outcome in [FakeLMSDownloader.Outcome.failure(.httpStatus(403)), .failure(.httpStatus(401)), .data(Data("<html><body>login</body></html>".utf8))] {
            let downloader = FakeLMSDownloader([outcome])
            await #expect(throws: LMSFetchError.loginRequired) {
                _ = try await fetcher(downloader).fetch(request, to: destination)
            }
            #expect(downloader.requests.count == 1)
        }
    }

    @Test func 암호화나_스트리밍_형식이면_다시_받지_않고_멈춘다() async throws {
        for data in [fakeMP4(moovContent: "trakencv"), Data("#EXTM3U\n#EXT-X-VERSION:3".utf8)] {
            let downloader = FakeLMSDownloader([.data(data)])
            await #expect(throws: LMSFetchError.protectedContent) {
                _ = try await fetcher(downloader).fetch(request, to: destination)
            }
            #expect(downloader.requests.count == 1)
            #expect(!FileManager.default.fileExists(atPath: destination.path))
        }
    }

    @Test func 네트워크_오류도_다시_받아_본다() async throws {
        let downloader = FakeLMSDownloader([.other(Timeout()), .data(fakeMP4())])
        defer { try? FileManager.default.removeItem(at: destination) }

        _ = try await fetcher(downloader).fetch(request, to: destination)

        #expect(downloader.requests.count == 2)
    }
}
