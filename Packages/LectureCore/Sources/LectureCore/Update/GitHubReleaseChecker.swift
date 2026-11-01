#if canImport(Darwin)
import Foundation

/// 공개 저장소의 GitHub 릴리스 목록을 읽는다. 로그인이나 토큰은 쓰지 않는다.
public struct GitHubReleaseChecker: AppUpdateChecking {
    public static let defaultURL = URL(string: "https://api.github.com/repos/uisong1/lecture-recorder/releases?per_page=20")!
    private let url: URL

    public init(url: URL = GitHubReleaseChecker.defaultURL) {
        self.url = url
    }

    public func latestRelease() async throws -> AppRelease? {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try AppReleaseParser.parse(data).first
    }
}
#endif
