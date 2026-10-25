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

    var converted: [URL] { lock.withLock { _converted } }

    func compress(from source: URL, to destination: URL) async throws -> TimeInterval {
        if let error { throw error }
        lock.withLock { _converted.append(source) }
        files.add(destination)
        return Self.duration
    }
}
