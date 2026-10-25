#if canImport(SwiftData)
import Foundation
import SwiftData

/// 녹음 중에 앱이 꺼졌다면, 남은 파일로 `Recording`을 만들어 목록에 되살린다.
@MainActor
public struct RecordingRecovery {
    /// 압축된 녹음(AAC 32kbps)의 비트레이트. 길이를 파일 크기로 어림할 때 쓴다.
    public static let bitsPerSecond: Double = 32_000
    /// 압축 전 녹음(PCM 16kHz 16비트 모노)의 비트레이트.
    public static let workingBitsPerSecond: Double = 256_000

    private let context: ModelContext
    private let storage: RecordingStorage
    private let files: any FileStoring
    private let journal: any RecordingJournaling
    private let calendar: Calendar

    public init(
        context: ModelContext,
        storage: RecordingStorage,
        files: any FileStoring = LocalFileStore(),
        journal: any RecordingJournaling,
        calendar: Calendar = .current
    ) {
        self.context = context
        self.storage = storage
        self.files = files
        self.journal = journal
        self.calendar = calendar
    }

    /// 저널에 남은 녹음이 있으면 되살린다. 되살린 녹음을 돌려주고, 할 일이 없으면 nil.
    @discardableResult
    public func recoverIfNeeded() throws -> Recording? {
        guard let pending = journal.load() else { return nil }
        let url = storage.url(for: pending.relativePath)
        guard files.fileExists(at: url) else {
            Log.recording.notice("복구할 파일 없음: \(pending.relativePath, privacy: .public)")
            journal.clear()
            return nil
        }
        let path = pending.relativePath
        let existing = try context.fetchCount(FetchDescriptor<Recording>(predicate: #Predicate { $0.relativePath == path }))
        guard existing == 0 else {
            journal.clear()
            return nil
        }

        let subject = try pending.subjectName.flatMap { name in
            try context.fetch(FetchDescriptor<Subject>(predicate: #Predicate { $0.name == name })).first
        }
        let bytes = files.fileSize(at: url) ?? 0
        let name = subject?.name ?? SubjectManager.unclassifiedName
        let recording = Recording(
            title: RecordingController.defaultTitle(subjectName: name, startedAt: pending.startedAt, calendar: calendar) + " (복구됨)",
            subject: subject,
            startedAt: pending.startedAt,
            duration: Double(bytes) * 8 / (RecordingStorage.isWorkingPath(pending.relativePath) ? Self.workingBitsPerSecond : Self.bitsPerSecond),
            relativePath: pending.relativePath
        )
        context.insert(recording)
        try context.save()
        journal.clear()
        Log.recording.notice("녹음 복구: \(pending.relativePath, privacy: .public)")
        return recording
    }
}
#endif
