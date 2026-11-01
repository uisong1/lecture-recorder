import Foundation
import Testing
@testable import LectureCore

@Suite struct AppReleaseParserTests {
    static let sha = String(repeating: "ab", count: 32)
    static let base = AppReleaseParser.allowedDownloadPrefix

    static func json(tag: String, asset: String? = nil, url: String? = nil, body: String? = nil, draft: Bool = false, prerelease: Bool = false) -> String {
        let build = tag.replacingOccurrences(of: "build-", with: "")
        let assetName = asset ?? "LectureRecorder-\(build).zip"
        let downloadURL = url ?? "\(base)\(tag)/\(assetName)"
        let text = body ?? "수정 내용\\nsha256: \(sha)"
        return """
        {"tag_name":"\(tag)","name":"빌드 \(build)","body":"\(text)","draft":\(draft),"prerelease":\(prerelease),
         "assets":[{"name":"\(assetName)","browser_download_url":"\(downloadURL)"}]}
        """
    }

    static func parse(_ items: [String]) throws -> [AppRelease] {
        try AppReleaseParser.parse(Data("[\(items.joined(separator: ","))]".utf8))
    }

    @Test func 빌드_번호_큰_순서로_돌려준다() throws {
        let releases = try Self.parse([Self.json(tag: "build-9"), Self.json(tag: "build-120"), Self.json(tag: "build-40")])
        #expect(releases.map(\.build) == [120, 40, 9])
        #expect(releases.first?.sha256 == Self.sha)
        #expect(releases.first?.downloadURL.absoluteString == "\(Self.base)build-120/LectureRecorder-120.zip")
    }

    @Test func 초안과_시험판과_다른_태그는_건너뛴다() throws {
        let releases = try Self.parse([
            Self.json(tag: "build-5", draft: true),
            Self.json(tag: "build-6", prerelease: true),
            Self.json(tag: "v1.0"),
            Self.json(tag: "build-abc"),
            Self.json(tag: "build-7"),
        ])
        #expect(releases.map(\.build) == [7])
    }

    @Test func 체크섬이_없거나_틀리면_건너뛴다() throws {
        let releases = try Self.parse([
            Self.json(tag: "build-1", body: "체크섬 없음"),
            Self.json(tag: "build-2", body: "sha256: 1234"),
            Self.json(tag: "build-3", body: "sha256: \(String(repeating: "z", count: 64))"),
        ])
        #expect(releases.isEmpty)
    }

    @Test func 대문자_체크섬은_소문자로_바꾼다() throws {
        let upper = String(repeating: "AB", count: 32)
        let releases = try Self.parse([Self.json(tag: "build-2", body: "SHA256: \(upper)")])
        #expect(releases.first?.sha256 == Self.sha)
    }

    @Test func 이_저장소_밖_주소나_다른_파일_이름은_거부한다() throws {
        let releases = try Self.parse([
            Self.json(tag: "build-1", url: "https://evil.example.com/LectureRecorder-1.zip"),
            Self.json(tag: "build-2", url: "http://github.com/uisong1/lecture-recorder/releases/download/build-2/LectureRecorder-2.zip"),
            Self.json(tag: "build-3", asset: "other.zip"),
        ])
        #expect(releases.isEmpty)
    }

    @Test func 릴리스가_없으면_빈_목록이다() throws {
        #expect(try Self.parse([]).isEmpty)
    }
}
