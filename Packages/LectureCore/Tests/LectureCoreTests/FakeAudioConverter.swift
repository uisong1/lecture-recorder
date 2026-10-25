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

    func compress(from source: URL, to destination: URL) async throws -> TimeInterval {
        if let error { throw error }
        lock.withLock { _converted.append(source) }
        files.add(destination)
        if let hook = whileConverting { await hook() }
        return Self.duration
    }
}
