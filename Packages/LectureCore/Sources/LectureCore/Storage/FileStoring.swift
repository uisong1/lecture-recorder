import Foundation

/// 파일 시스템 접근. 테스트에서는 메모리 안의 가짜 구현을 쓴다.
public protocol FileStoring: Sendable {
    func fileExists(at url: URL) -> Bool
    func createDirectory(at url: URL) throws
    func moveItem(at source: URL, to destination: URL) throws
    func removeItem(at url: URL) throws
    /// `source`를 `destination`으로 복사한다. 이미 있으면 새 파일로 바꾼다 (복사에 실패하면 기존 파일은 그대로 둔다).
    func copyItem(at source: URL, to destination: URL) throws
    /// 파일 크기(바이트). 없거나 알 수 없으면 nil.
    func fileSize(at url: URL) -> Int64?
    /// 남은 저장 공간(바이트). 알 수 없으면 nil.
    func availableCapacity(at url: URL) -> Int64?
}

/// `FileManager`를 쓰는 실제 구현.
public struct LocalFileStore: FileStoring {
    public init() {}

    public func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    public func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func moveItem(at source: URL, to destination: URL) throws {
        try FileManager.default.moveItem(at: source, to: destination)
    }

    public func removeItem(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    public func copyItem(at source: URL, to destination: URL) throws {
        let manager = FileManager.default
        guard fileExists(at: destination) else {
            try manager.copyItem(at: source, to: destination)
            return
        }
        // 같은 폴더에 먼저 복사해 두고 바꿔 끼운다. 복사가 실패해도 기존 파일이 지워지지 않는다.
        let temporary = destination.deletingLastPathComponent().appending(path: ".\(UUID().uuidString).copying")
        do {
            try manager.copyItem(at: source, to: temporary)
            _ = try manager.replaceItemAt(destination, withItemAt: temporary)
        } catch {
            try? manager.removeItem(at: temporary)
            throw error
        }
    }

    public func fileSize(at url: URL) -> Int64? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        return (attributes?[.size] as? NSNumber)?.int64Value
    }

    public func availableCapacity(at url: URL) -> Int64? {
        #if os(macOS)
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
        #else
        let attributes = try? FileManager.default.attributesOfFileSystem(forPath: url.path(percentEncoded: false))
        return (attributes?[.systemFreeSize] as? NSNumber)?.int64Value
        #endif
    }
}
