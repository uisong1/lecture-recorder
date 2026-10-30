#if canImport(Darwin)
import AVFoundation
import Foundation

/// `URLSession`으로 영상을 받는다. 웹뷰 쿠키와 Referer를 헤더로 직접 붙이고, **Range 헤더는 보내지 않는다** (일부만 받아져 파일이 깨진다).
/// 시스템 쿠키 저장소와 캐시는 쓰지 않아서 이 앱의 다른 요청과 섞이지 않는다.
public struct URLSessionLMSDownloader: LMSDownloading {
    public init() {}

    public func download(_ request: LMSDownloadRequest, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> LMSDownloadResult {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpShouldHandleCookies = false
        urlRequest.cachePolicy = .reloadIgnoringLocalCacheData
        if let referer = request.referer { urlRequest.setValue(referer.absoluteString, forHTTPHeaderField: "Referer") }
        if let cookie = request.cookieHeader { urlRequest.setValue(cookie, forHTTPHeaderField: "Cookie") }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 60
        let delegate = DownloadDelegate(destination: destination, progress: progress)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let task = session.downloadTask(with: urlRequest)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                delegate.start(continuation)
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        private let destination: URL
        private let progress: @Sendable (Double) -> Void
        private let lock = NSLock()
        private var continuation: CheckedContinuation<LMSDownloadResult, Error>?

        init(destination: URL, progress: @escaping @Sendable (Double) -> Void) {
            self.destination = destination
            self.progress = progress
        }

        func start(_ continuation: CheckedContinuation<LMSDownloadResult, Error>) {
            lock.withLock { self.continuation = continuation }
        }

        /// 한 번만 이어 간다 (완료 알림과 오류 알림이 둘 다 올 수 있다).
        private func finish(_ result: Result<LMSDownloadResult, Error>) {
            let pending = lock.withLock { () -> CheckedContinuation<LMSDownloadResult, Error>? in
                defer { continuation = nil }
                return continuation
            }
            pending?.resume(with: result)
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            guard totalBytesExpectedToWrite > 0 else { return }
            progress(min(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), 1))
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            guard let response = downloadTask.response as? HTTPURLResponse else {
                finish(.failure(LMSDownloadError.network("응답이 없습니다")))
                return
            }
            // 200만 전체를 받은 것이다. 206(일부)이나 로그인 페이지로의 이동 등은 실패로 본다.
            guard response.statusCode == 200 else {
                finish(.failure(LMSDownloadError.httpStatus(response.statusCode)))
                return
            }
            do {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: location, to: destination)
                let size = (try FileManager.default.attributesOfItem(atPath: destination.path(percentEncoded: false))[.size] as? NSNumber)?.int64Value ?? 0
                let expected = response.expectedContentLength
                if expected > 0, response.value(forHTTPHeaderField: "Content-Encoding") == nil, size != expected {
                    finish(.failure(LMSDownloadError.incomplete(expected: expected, actual: size)))
                    return
                }
                finish(.success(LMSDownloadResult(lastModified: Self.httpDate(response.value(forHTTPHeaderField: "Last-Modified")))))
            } catch {
                finish(.failure(LMSDownloadError.network(error.localizedDescription)))
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let error { finish(.failure(LMSDownloadError.network(error.localizedDescription))) }
        }

        private static func httpDate(_ text: String?) -> Date? {
            guard let text else { return nil }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "GMT")
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            return formatter.date(from: text)
        }
    }
}

/// 받은 영상을 AVFoundation으로 열어 재생 길이가 있는지 본다.
public enum SystemMediaPlayability {
    public static func isPlayable(_ url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration), duration.isNumeric, duration.seconds > 0 else { return false }
        return (try? await asset.load(.isPlayable)) ?? false
    }
}
#endif
