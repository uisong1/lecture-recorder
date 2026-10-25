#if canImport(SwiftData)
import Foundation
import SwiftData

/// 녹음 중에 앱이 꺼졌다면, 남은 파일로 `Recording`을 만들어 목록에 되살린다.
@MainActor
public struct RecordingRecovery {
    /// 압축된 녹음(AAC 32kbps)의 비트레이트. 길이를 파일 크기로 어림할 때 쓴다.
    public static let bitsPerSecond = Double(RecordingFormat.compressedBitRate)
    /// 압축 전 녹음(PCM 16kHz 16비트 모노)의 비트레이트.
    public static let workingBitsPerSecond = Double(RecordingFormat.workingBytesPerSecond * 8)

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
    /// 저장에 실패한 뒤 새 녹음 때문에 따로 보관된 기록(`keepUnsaved`)도 함께 되살린다. 여럿이면 가장 먼저 되살린 녹음을 돌려준다.
    @discardableResult
    public func recoverIfNeeded() throws -> Recording? {
        var first: Recording?
        var firstError: Error?
        var candidates: [(PendingRecording, () -> Void)] = []
        if let pending = journal.load() { candidates.append((pending, { journal.clear() })) }
        for pending in journal.loadUnsaved() {
            let path = pending.relativePath
            candidates.append((pending, { journal.clearUnsaved(relativePath: path) }))
        }
        for (pending, clearEntry) in candidates {
            do {
                if let recording = try recover(pending, clearing: clearEntry), first == nil { first = recording }
            } catch {
                // 한 건이 실패해도 나머지는 되살린다. 실패한 기록은 저널에 남아 다음 실행 때 다시 시도한다.
                Log.recording.error("녹음 복구 실패 \(pending.relativePath, privacy: .public): \(error.localizedDescription, privacy: .public)")
                firstError = firstError ?? error
            }
        }
        if let firstError, first == nil { throw firstError }
        return first
    }

    private func recover(_ pending: PendingRecording, clearing clearEntry: () -> Void) throws -> Recording? {
        let url = storage.url(for: pending.relativePath)
        guard files.fileExists(at: url) else {
            Log.recording.notice("복구할 파일 없음: \(pending.relativePath, privacy: .public)")
            clearEntry()
            return nil
        }
        let path = pending.relativePath
        let existing = try context.fetchCount(FetchDescriptor<Recording>(predicate: #Predicate { $0.relativePath == path }))
        guard existing == 0 else {
            clearEntry()
            return nil
        }

        let subject = try pending.subjectName.flatMap { name in
            try context.fetch(FetchDescriptor<Subject>(predicate: #Predicate { $0.name == name })).first
        }
        let bytes = files.fileSize(at: url) ?? 0
        let name = subject?.name ?? SubjectManager.unclassifiedName
        let recording = Recording(
            title: RecordingController.defaultTitle(subjectName: name, startedAt: pending.startedAt, calendar: calendar),
            subject: subject,
            startedAt: pending.startedAt,
            duration: Double(bytes) * 8 / (RecordingStorage.isWorkingPath(pending.relativePath) ? Self.workingBitsPerSecond : Self.bitsPerSecond),
            relativePath: pending.relativePath
        )
        recording.wasRecovered = true
        context.insert(recording)
        // 녹음이 끊긴 지점보다 뒤의 북마크는 길이 어림값 안으로 맞춘다.
        for (index, time) in pending.bookmarkTimes.enumerated() {
            let note = pending.bookmarkNotes.indices.contains(index) ? pending.bookmarkNotes[index] : ""
            context.insert(Bookmark(time: min(max(time, 0), recording.duration), note: note, createdAt: pending.startedAt, recording: recording))
        }
        try context.save()
        clearEntry()
        Log.recording.notice("녹음 복구: \(pending.relativePath, privacy: .public)")
        return recording
    }
}
#endif
