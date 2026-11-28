import Foundation
@testable import LectureCore

/// 변환 결과 파일을 가짜 파일 시스템에 만들어 주는 가짜 변환기.
final class FakeAudioConverter: AudioConverting, @unchecked Sendable {
    static let duration: TimeInterval = 123

    private let lock = NSLock()
    private var _error: Error?
    private var _converted: [URL] = []
    private let files: FakeFileStore

    init(files: FakeFileStore) { self.files = files }

    var error: Error? {
        get { lock.withLock { _error } }
        set { lock.withLock { _error = newValue } }
    }

    /// 변환이 끝나기 직전에 부르는 동작. 압축하는 동안 일어나는 일(예: 과목 이동)을 흉내 낸다.
    var whileConverting: (@MainActor () -> Void)? {
        get { lock.withLock { _whileConverting } }
        set { lock.withLock { _whileConverting = newValue } }
    }
    private var _whileConverting: (@MainActor () -> Void)?

    var converted: [URL] { lock.withLock { _converted } }

    /// 파일마다 잴 길이. 없으면 `duration`(변환 결과와 같은 길이)으로 본다.
    var durations: [URL: TimeInterval] {
        get { lock.withLock { _durations } }
        set { lock.withLock { _durations = newValue } }
    }
    private var _durations: [URL: TimeInterval] = [:]

    /// 변환을 시작하면 부르는 동작. 변환 중에 같은 녹음을 또 압축하는 경우를 흉내 낸다.
    var onStart: (@MainActor () async -> Void)? {
        get { lock.withLock { _onStart } }
        set { lock.withLock { _onStart = newValue } }
    }
    private var _onStart: (@MainActor () async -> Void)?

    /// 길이를 재지 못하는(열리지 않는) 파일.
    var unreadable: Set<URL> {
        get { lock.withLock { _unreadable } }
        set { lock.withLock { _unreadable = newValue } }
    }
    private var _unreadable: Set<URL> = []

    func duration(of url: URL) async throws -> TimeInterval {
        guard files.fileExists(at: url), !unreadable.contains(url.standardizedFileURL) else { throw CocoaError(.fileReadCorruptFile) }
        return durations[url.standardizedFileURL] ?? Self.duration
    }

    func compress(from source: URL, to destination: URL) async throws -> TimeInterval {
        if let error { throw error }
        lock.withLock { _converted.append(source) }
        if let onStart { await onStart() }
        files.add(destination)
        if let hook = whileConverting { await hook() }
        return Self.duration
    }
}
