import Foundation
@testable import LectureCore

/// 메모리 안에서 파일 존재 여부만 흉내 내는 가짜 파일 시스템.
final class FakeFileStore: FileStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var paths: Set<String> = []
    var capacity: Int64? = 10_000_000_000
    var failNextMove = false
    var sizes: [String: Int64] = [:]
    /// 파일 수정 시각 (경로 → 시각). 없으면 알 수 없는 것으로 본다.
    var modificationDates: [String: Date] = [:]
    private var directories: Set<String> = []

    init(files: [URL] = []) {
        paths = Set(files.map(\.standardizedFileURL.path))
    }

    var allPaths: Set<String> { lock.withLock { paths } }

    func add(_ url: URL) { lock.withLock { _ = paths.insert(url.standardizedFileURL.path) } }

    /// `fileExists`를 부른 횟수 (불필요한 파일 확인이 없는지 볼 때 쓴다).
    var fileExistsCalls: Int { lock.withLock { existsCalls } }
    private var existsCalls = 0

    func fileExists(at url: URL) -> Bool {
        lock.withLock {
            existsCalls += 1
            return paths.contains(url.standardizedFileURL.path)
        }
    }

    func createDirectory(at url: URL) throws {
        add(url)
        lock.withLock { _ = directories.insert(url.standardizedFileURL.path) }
    }

    func isDirectory(at url: URL) -> Bool {
        lock.withLock {
            let path = url.standardizedFileURL.path
            return directories.contains(path) || paths.contains { $0.hasPrefix(path + "/") }
        }
    }

    func modificationDate(at url: URL) -> Date? {
        lock.withLock { modificationDates[url.standardizedFileURL.path] }
    }

    func removeEmptyDirectory(at url: URL) throws {
        try lock.withLock {
            let path = url.standardizedFileURL.path
            guard !paths.contains(where: { $0.hasPrefix(path + "/") }) else { throw POSIXError(.ENOTEMPTY) }
            guard paths.remove(path) != nil else { throw CocoaError(.fileNoSuchFile) }
            directories.remove(path)
        }
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
    /// true면 다음 복사본이 원본보다 1바이트 크게 만들어진다 (중간에 끊긴 복사를 흉내 낸다).
    var corruptNextCopy = false

    func copyItem(at source: URL, to destination: URL) throws {
        try lock.withLock {
            if failNextCopy {
                failNextCopy = false
                throw CocoaError(.fileWriteOutOfSpace)
            }
            guard paths.contains(source.standardizedFileURL.path) else { throw CocoaError(.fileNoSuchFile) }
            paths.insert(destination.standardizedFileURL.path)
            if let size = sizes[source.standardizedFileURL.path] {
                sizes[destination.standardizedFileURL.path] = size + (corruptNextCopy ? 1 : 0)
            }
            corruptNextCopy = false
        }
    }

    /// 휴지통으로 보낸 파일 경로. 목록에서는 사라진다.
    private(set) var trashed: [String] = []
    var failNextTrash = false

    func trashItem(at url: URL) throws {
        try lock.withLock {
            if failNextTrash {
                failNextTrash = false
                throw CocoaError(.fileWriteNoPermission)
            }
            let path = url.standardizedFileURL.path
            guard paths.remove(path) != nil else { throw CocoaError(.fileNoSuchFile) }
            trashed.append(path)
        }
    }

    func removeItem(at url: URL) throws {
        try lock.withLock {
            let path = url.standardizedFileURL.path
            let children = paths.filter { $0.hasPrefix(path + "/") }
            guard paths.remove(path) != nil || !children.isEmpty else { throw CocoaError(.fileNoSuchFile) }
            // 폴더를 지우면 그 안의 항목도 함께 사라진다.
            paths.subtract(children)
            directories.remove(path)
            for child in children { sizes[child] = nil }
        }
    }

    var failNextListing = false

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        try lock.withLock {
            if failNextListing {
                failNextListing = false
                throw CocoaError(.fileReadNoPermission)
            }
            let directory = url.standardizedFileURL.path
            let prefix = directory + "/"
            var names: Set<String> = []
            for path in paths where path.hasPrefix(prefix) {
                if let first = path.dropFirst(prefix.count).split(separator: "/", maxSplits: 1).first { names.insert(String(first)) }
            }
            guard paths.contains(directory) || !names.isEmpty else { throw CocoaError(.fileReadNoSuchFile) }
            return names.sorted().map { url.appending(path: $0) }
        }
    }

    func fileSize(at url: URL) -> Int64? {
        lock.withLock { sizes[url.standardizedFileURL.path] }
    }

    func availableCapacity(at url: URL) -> Int64? { capacity }
}
