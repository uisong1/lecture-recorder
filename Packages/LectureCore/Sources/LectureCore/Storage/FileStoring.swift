import Foundation

/// 파일 시스템 접근. 테스트에서는 메모리 안의 가짜 구현을 쓴다.
public protocol FileStoring: Sendable {
    func fileExists(at url: URL) -> Bool
    func createDirectory(at url: URL) throws
    func moveItem(at source: URL, to destination: URL) throws
    func removeItem(at url: URL) throws
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
