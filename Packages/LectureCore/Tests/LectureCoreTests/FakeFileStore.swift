import Foundation
@testable import LectureCore

/// 메모리 안에서 파일 존재 여부만 흉내 내는 가짜 파일 시스템.
final class FakeFileStore: FileStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var paths: Set<String> = []
    var capacity: Int64? = 10_000_000_000
    var failNextMove = false
    var sizes: [String: Int64] = [:]

    init(files: [URL] = []) {
        paths = Set(files.map(\.standardizedFileURL.path))
    }

    var allPaths: Set<String> { lock.withLock { paths } }

    func add(_ url: URL) { lock.withLock { _ = paths.insert(url.standardizedFileURL.path) } }

    func fileExists(at url: URL) -> Bool {
        lock.withLock { paths.contains(url.standardizedFileURL.path) }
    }

    func createDirectory(at url: URL) throws {
        add(url)
    }

    func moveItem(at source: URL, to destination: URL) throws {
        try lock.withLock {
            if failNextMove {
                failNextMove = false
                throw CocoaError(.fileWriteUnknown)
            }
            let from = source.standardizedFileURL.path
            let to = destination.standardizedFileURL.path
            guard paths.remove(from) != nil else { throw CocoaError(.fileNoSuchFile) }
            guard !paths.contains(to) else { throw CocoaError(.fileWriteFileExists) }
            paths.insert(to)
        }
    }

    var failNextCopy = false

    func copyItem(at source: URL, to destination: URL) throws {
        try lock.withLock {
            if failNextCopy {
                failNextCopy = false
                throw CocoaError(.fileWriteOutOfSpace)
            }
            guard paths.contains(source.standardizedFileURL.path) else { throw CocoaError(.fileNoSuchFile) }
            paths.insert(destination.standardizedFileURL.path)
        }
    }

    func removeItem(at url: URL) throws {
        try lock.withLock {
            guard paths.remove(url.standardizedFileURL.path) != nil else { throw CocoaError(.fileNoSuchFile) }
        }
    }

    func fileSize(at url: URL) -> Int64? {
        lock.withLock { sizes[url.standardizedFileURL.path] }
    }

    func availableCapacity(at url: URL) -> Int64? { capacity }
}
