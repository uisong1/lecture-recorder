import Foundation

public struct LMSDownloadRequest: Equatable, Sendable {
    public let url: URL
    public let referer: URL?
    /// 웹뷰 쿠키에서 이 주소에 맞는 것만 모은 `Cookie` 헤더 값.
    public let cookieHeader: String?

    public init(url: URL, referer: URL?, cookieHeader: String?) {
        self.url = url
        self.referer = referer
        self.cookieHeader = cookieHeader
    }
}

public struct LMSDownloadResult: Equatable, Sendable {
    /// 서버가 알려 준 파일의 수정 시각. 영상이 올라온 날로 어림해 쓴다.
    public var lastModified: Date?

    public init(lastModified: Date? = nil) {
        self.lastModified = lastModified
    }
}

public enum LMSDownloadError: Error, Equatable, Sendable {
    /// 200이 아닌 응답. 206(일부만)도 여기에 든다 — Range 없이 전체를 받아야 한다.
    case httpStatus(Int)
    /// 받은 크기가 서버가 알려 준 크기와 다르다.
    case incomplete(expected: Int64, actual: Int64)
    case network(String)
}

/// 영상을 받는다. 실제 구현은 `URLSession`이고 테스트에서는 가짜를 쓴다.
/// 구현은 **Range 헤더를 보내지 않고** 처음부터 전체를 받아야 한다.
public protocol LMSDownloading: Sendable {
    func download(_ request: LMSDownloadRequest, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> LMSDownloadResult
}

public enum LMSFetchError: Error, Equatable, LocalizedError {
    /// 로그인이 만료됐다 (401/403이거나 영상 대신 로그인 페이지가 왔다).
    case loginRequired
    /// 암호화·DRM·스트리밍 형식이다. 우회하지 않고 멈춘다.
    case protectedContent
    case invalidFile
    case downloadFailed(String)

    public var errorDescription: String? {
        switch self {
        case .loginRequired: "LMS 로그인이 만료됐습니다. LMS 창에서 다시 로그인한 뒤 시도해 주세요."
        case .protectedContent: "이 영상은 암호화되었거나 스트리밍 형식이어서 가져오지 않습니다. 우회하지 않고 LMS 가져오기를 멈췄습니다."
        case .invalidFile: "받은 파일이 정상적인 mp4가 아닙니다."
        case .downloadFailed(let reason): "영상을 받지 못했습니다: \(reason)"
        }
    }

    /// 다시 받아 봐야 소용없는 오류.
    var isFinal: Bool { self == .loginRequired || self == .protectedContent }
}

/// 영상을 받고 정상 mp4인지 확인하고, 실패하면 다시 받는다.
/// 확인 순서: HTTP 상태 → 크기 → HTML/스트리밍 목록 여부 → `ftyp` 상자 → 암호화 표시 → 재생 길이(`isPlayable`).
public struct LMSVideoFetcher: Sendable {
    public static let defaultAttempts = 3

    private let downloader: any LMSDownloading
    private let attempts: Int
    private let retryDelays: [TimeInterval]
    private let sleep: @Sendable (TimeInterval) async -> Void
    private let isPlayable: @Sendable (URL) async -> Bool

    /// - Parameters:
    ///   - isPlayable: 받은 파일이 재생 길이를 가졌는지 (실제로는 AVFoundation으로 연다).
    ///   - sleep: 다시 받기 전에 기다린다. 테스트에서는 바로 돌아오는 것을 넘긴다.
    public init(
        downloader: any LMSDownloading,
        attempts: Int = LMSVideoFetcher.defaultAttempts,
        retryDelays: [TimeInterval] = [2, 5],
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) },
        isPlayable: @escaping @Sendable (URL) async -> Bool = { _ in true }
    ) {
        self.downloader = downloader
        self.attempts = max(attempts, 1)
        self.retryDelays = retryDelays
        self.sleep = sleep
        self.isPlayable = isPlayable
    }

    /// `destination`에 영상을 받는다. 실패한 시도의 파일은 지운다.
    public func fetch(_ request: LMSDownloadRequest, to destination: URL, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> LMSDownloadResult {
        var lastError: LMSFetchError = .invalidFile
        for attempt in 1...attempts {
            do {
                return try await attemptOnce(request, to: destination, progress: progress)
            } catch let error as LMSFetchError {
                try? FileManager.default.removeItem(at: destination)
                lastError = error
                if error.isFinal { throw error }
            } catch is CancellationError {
                try? FileManager.default.removeItem(at: destination)
                throw CancellationError()
            }
            if attempt < attempts {
                await sleep(retryDelays.isEmpty ? 0 : retryDelays[min(attempt - 1, retryDelays.count - 1)])
            }
        }
        throw lastError
    }

    private func attemptOnce(_ request: LMSDownloadRequest, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> LMSDownloadResult {
        try? FileManager.default.removeItem(at: destination)
        let result: LMSDownloadResult
        do {
            result = try await downloader.download(request, to: destination, progress: progress)
        } catch let error as LMSDownloadError {
            switch error {
            case .httpStatus(401), .httpStatus(403): throw LMSFetchError.loginRequired
            case .httpStatus(let code): throw LMSFetchError.downloadFailed("서버 응답 \(code)")
            case .incomplete(let expected, let actual): throw LMSFetchError.downloadFailed("\(actual)/\(expected) 바이트만 받아졌습니다")
            case .network(let reason): throw LMSFetchError.downloadFailed(reason)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw LMSFetchError.downloadFailed(error.localizedDescription)
        }
        try validate(destination)
        guard await isPlayable(destination) else { throw LMSFetchError.invalidFile }
        return result
    }

    private func validate(_ file: URL) throws {
        let header = (try? FileHandle(forReadingFrom: file)).flatMap { handle -> Data? in
            defer { try? handle.close() }
            return try? handle.read(upToCount: 256)
        } ?? Data()
        if MediaFileValidator.hasFtypBox(header) {
            if MediaFileValidator.isEncrypted(at: file) { throw LMSFetchError.protectedContent }
            return
        }
        if MediaFileValidator.looksLikeStreamingManifest(header) { throw LMSFetchError.protectedContent }
        if MediaFileValidator.looksLikeHTML(header) { throw LMSFetchError.loginRequired }
        throw LMSFetchError.invalidFile
    }
}
