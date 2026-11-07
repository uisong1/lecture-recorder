#if canImport(Darwin)
import Foundation
import Security

/// `URLSession`으로 Canvas·LearningX·commons에 요청을 보낸다. 쿠키는 이 객체 안(메모리)에만 두고 디스크에 남기지 않는다.
/// 요청마다 새 객체를 만들어 쓰면 이전 세션이 남지 않는다.
public final class URLSessionCanvasClient: CanvasHTTPClient, @unchecked Sendable {
    private let session: URLSession
    private let cookies: HTTPCookieStorage

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .always
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 120
        cookies = configuration.httpCookieStorage ?? HTTPCookieStorage()
        session = URLSession(configuration: configuration)
    }

    public func send(_ request: URLRequest) async throws -> CanvasHTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CanvasError.invalidResponse }
        return CanvasHTTPResponse(data: data, statusCode: http.statusCode, url: http.url ?? request.url ?? URL(fileURLWithPath: "/"))
    }

    public func cookieValue(named name: String, for url: URL) async -> String? {
        cookies.cookies(for: url)?.first { $0.name == name }?.value
    }
}

/// Canvas 개인 액세스 토큰을 Keychain에만 보관한다. 파일·UserDefaults·로그에는 남기지 않는다.
public final class KeychainCanvasTokenStore: CanvasTokenStoring, @unchecked Sendable {
    public struct KeychainError: Error, LocalizedError {
        public let status: OSStatus
        public var errorDescription: String? { "Keychain 오류 (\(status))" }
    }

    private let service: String
    private let account = "canvas-access-token"

    public init(service: String = "LectureRecorder.Canvas") {
        self.service = service
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    public func loadToken() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        guard let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func saveToken(_ token: String) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        try deleteToken()
        guard !trimmed.isEmpty else { return }
        var query = baseQuery
        query[kSecValueData as String] = Data(trimmed.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    public func deleteToken() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}
#endif
