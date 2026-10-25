import Foundation

/// 녹음이 시작됐지만 아직 정상적으로 저장되지 않은 녹음. 앱이 녹음 중에 꺼졌을 때 복구에 쓴다.
public struct PendingRecording: Codable, Equatable, Sendable {
    /// `Recordings/` 기준 상대 경로.
    public var relativePath: String
    /// nil이면 미분류.
    public var subjectName: String?
    public var startedAt: Date

    public init(relativePath: String, subjectName: String?, startedAt: Date) {
        self.relativePath = relativePath
        self.subjectName = subjectName
        self.startedAt = startedAt
    }
}

/// 진행 중인 녹음을 기록해 두는 저널. 녹음을 시작하면 쓰고, 정상 저장되면 지운다.
public protocol RecordingJournaling: Sendable {
    func load() -> PendingRecording?
    func save(_ pending: PendingRecording) throws
    func clear()
}

/// JSON 파일 하나에 기록하는 저널.
public struct FileRecordingJournal: RecordingJournaling {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func load() -> PendingRecording? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(PendingRecording.self, from: data)
        } catch {
            #if canImport(os)
            Log.recording.error("녹음 저널을 읽지 못함: \(error.localizedDescription, privacy: .public)")
            #endif
            return nil
        }
    }

    public func save(_ pending: PendingRecording) throws {
        try JSONEncoder().encode(pending).write(to: url, options: .atomic)
    }

    public func clear() {
        do {
            try FileManager.default.removeItem(at: url)
        } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            // 이미 없다.
        } catch {
            #if canImport(os)
            Log.recording.error("녹음 저널을 지우지 못함: \(error.localizedDescription, privacy: .public)")
            #endif
        }
    }
}

/// 메모리에만 기록하는 저널. 테스트와 미리보기에서 쓴다.
public final class InMemoryRecordingJournal: RecordingJournaling, @unchecked Sendable {
    private let lock = NSLock()
    private var pending: PendingRecording?

    public init(pending: PendingRecording? = nil) {
        self.pending = pending
    }

    public func load() -> PendingRecording? { lock.withLock { pending } }
    public func save(_ pending: PendingRecording) throws { lock.withLock { self.pending = pending } }
    public func clear() { lock.withLock { pending = nil } }
}
