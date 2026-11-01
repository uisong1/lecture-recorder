import Foundation

/// GitHub Releases에 올라온 앱 빌드 하나. 태그는 `build-<번호>`이고 번호는 커밋 개수라서 클수록 새 버전이다.
public struct AppRelease: Equatable, Sendable {
    public let build: Int
    public let title: String
    public let notes: String
    public let downloadURL: URL
    /// 받은 zip이 온전한지 확인하는 SHA-256 (소문자 16진수 64자).
    public let sha256: String

    public init(build: Int, title: String, notes: String, downloadURL: URL, sha256: String) {
        self.build = build
        self.title = title
        self.notes = notes
        self.downloadURL = downloadURL
        self.sha256 = sha256
    }
}

/// GitHub 릴리스 목록(JSON)에서 앱 업데이트 후보를 골라낸다.
public enum AppReleaseParser {
    /// 이 저장소의 릴리스 파일만 받는다. 업데이트 도우미 스크립트에 넘기는 주소라서 그 밖의 주소는 거부한다.
    public static let allowedDownloadPrefix = "https://github.com/uisong1/lecture-recorder/releases/download/"
    public static let tagPrefix = "build-"

    private struct Payload: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
        }
        let tag_name: String
        let name: String?
        let body: String?
        let draft: Bool?
        let prerelease: Bool?
        let assets: [Asset]
    }

    /// 쓸 수 있는 릴리스를 빌드 번호 큰 순서로 돌려준다. 형식이 맞지 않는 항목은 건너뛴다.
    public static func parse(_ data: Data) throws -> [AppRelease] {
        let payloads = try JSONDecoder().decode([Payload].self, from: data)
        return payloads.compactMap(release(from:)).sorted { $0.build > $1.build }
    }

    private static func release(from payload: Payload) -> AppRelease? {
        guard payload.draft != true, payload.prerelease != true,
              payload.tag_name.hasPrefix(tagPrefix),
              let build = Int(payload.tag_name.dropFirst(tagPrefix.count)), build > 0,
              let asset = payload.assets.first(where: { $0.name == "LectureRecorder-\(build).zip" }),
              asset.browser_download_url.hasPrefix(allowedDownloadPrefix),
              let url = URL(string: asset.browser_download_url),
              let sha = checksum(in: payload.body ?? "")
        else { return nil }
        return AppRelease(
            build: build,
            title: payload.name ?? payload.tag_name,
            notes: payload.body ?? "",
            downloadURL: url,
            sha256: sha
        )
    }

    /// 본문의 `sha256: <64자>` 줄을 찾는다.
    static func checksum(in body: String) -> String? {
        for line in body.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.lowercased().hasPrefix("sha256:") else { continue }
            let value = trimmed.dropFirst("sha256:".count).trimmingCharacters(in: .whitespaces).lowercased()
            if value.count == 64, value.allSatisfy({ $0.isHexDigit }) { return value }
        }
        return nil
    }
}
