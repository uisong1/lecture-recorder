import Foundation

/// 파일 시스템 접근. 테스트에서는 메모리 안의 가짜 구현을 쓴다.
public protocol FileStoring: Sendable {
    func fileExists(at url: URL) -> Bool
    func createDirectory(at url: URL) throws
    func moveItem(at source: URL, to destination: URL) throws
    func removeItem(at url: URL) throws
    /// `url`을 영구 삭제하지 않고 휴지통으로 보낸다. 실패하면 파일은 그대로다.
    func trashItem(at url: URL) throws
    /// `source`를 `destination`으로 복사한다. 이미 있으면 새 파일로 바꾼다 (복사에 실패하면 기존 파일은 그대로 둔다).
    func copyItem(at source: URL, to destination: URL) throws
    /// 폴더인지. 심볼릭 링크는 따라가지 않는다 (링크는 폴더가 아닌 항목으로 본다).
    func isDirectory(at url: URL) -> Bool
    /// 마지막으로 고친 시각. 알 수 없으면 nil.
    func modificationDate(at url: URL) -> Date?
    /// **비어 있는** 폴더만 지운다. 안에 무엇이든 있으면 지우지 않고 오류를 던진다 (`removeItem`처럼 안의 것을 따라 지우지 않는다).
    func removeEmptyDirectory(at url: URL) throws
    /// 폴더 바로 아래의 항목들 (숨김 파일 포함). 폴더가 없으면 오류.
    func contentsOfDirectory(at url: URL) throws -> [URL]
    /// 파일 크기(바이트). 없거나 알 수 없으면 nil.
    func fileSize(at url: URL) -> Int64?
    /// 남은 저장 공간(바이트). 알 수 없으면 nil.
    func availableCapacity(at url: URL) -> Int64?
}

/// `FileManager`를 쓰는 실제 구현.
public struct LocalFileStore: FileStoring {
    /// 휴지통 대신 파일을 옮겨 둘 폴더. UI 테스트가 사용자의 실제 휴지통을 건드리지 않게 할 때만 쓴다.
    private let trashDirectory: URL?

    public init(trashDirectory: URL? = nil) {
        self.trashDirectory = trashDirectory
    }

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

    public func trashItem(at url: URL) throws {
        if let trashDirectory {
            try FileManager.default.createDirectory(at: trashDirectory, withIntermediateDirectories: true)
            // 같은 이름이 이미 있어도 덮어쓰지 않도록 이름 앞에 고유한 접두를 붙인다.
            try FileManager.default.moveItem(at: url, to: trashDirectory.appending(path: "\(UUID().uuidString)-\(url.lastPathComponent)"))
            return
        }
        #if os(macOS)
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        #else
        // Linux(CI)에는 휴지통이 없다. 앱은 macOS에서만 돈다.
        throw CocoaError(.featureUnsupported)
        #endif
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

    public func isDirectory(at url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        return values?.isDirectory == true && values?.isSymbolicLink != true
    }

    public func modificationDate(at url: URL) -> Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        return attributes?[.modificationDate] as? Date
    }

    public func removeEmptyDirectory(at url: URL) throws {
        // rmdir은 폴더가 비어 있을 때만 지운다. 비어 있지 않으면 ENOTEMPTY로 실패한다.
        guard rmdir(url.path(percentEncoded: false)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    public func contentsOfDirectory(at url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])
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
