#if canImport(SwiftData)
import Foundation
import SwiftData

/// mp4/m4a 파일 하나를 녹음 목록으로 가져온다. 영상이면 소리만 m4a로 꺼내고, m4a는 그대로 복사한다.
///
/// 파일은 임시 이름으로 먼저 쓰고, 길이를 확인한 뒤에만 제자리로 옮긴다. 실패하면 임시 파일을 지워서
/// 목록에 없는 반쪽짜리 파일이 `Recordings/`에 남지 않는다. 원본 파일은 건드리지 않는다.
@MainActor
public struct MediaImporter {
    /// 여유 공간이 파일 크기보다 이만큼은 더 있어야 가져온다.
    public static let spareBytes: Int64 = 50_000_000

    private let context: ModelContext
    private let storage: RecordingStorage
    private let files: any FileStoring
    private let extractor: any AudioExtracting
    private let durations: any AudioDurationReading
    private let calendar: Calendar

    public init(
        context: ModelContext,
        storage: RecordingStorage,
        files: any FileStoring = LocalFileStore(),
        extractor: any AudioExtracting,
        durations: any AudioDurationReading,
        calendar: Calendar = .current
    ) {
        self.context = context
        self.storage = storage
        self.files = files
        self.extractor = extractor
        self.durations = durations
        self.calendar = calendar
    }

    /// - Parameters:
    ///   - subject: nil이면 미분류.
    ///   - startedAt: 수업 날짜·시각. 파일 이름과 제목에 쓴다.
    ///   - title: 비어 있으면 "과목 10월 28일 13:30" 형식으로 만든다.
    @discardableResult
    public func importFile(at source: URL, subject: Subject?, startedAt: Date, title: String? = nil) async throws -> Recording {
        let name = source.lastPathComponent
        guard let kind = MediaFileKind(fileName: name) else { throw MediaImportError.unsupportedType(name) }
        guard MediaFileValidator.hasFtypBox(at: source) else { throw MediaImportError.notMediaFile(name) }
        if let free = files.availableCapacity(at: storage.root), let size = files.fileSize(at: source), free < size + Self.spareBytes {
            throw MediaImportError.notEnoughSpace
        }

        let relativePath = storage.newRelativePath(subjectName: subject?.name, semester: subject?.semester, startedAt: startedAt, calendar: calendar)
        let destination = storage.url(for: relativePath)
        let temporary = storage.url(for: RecordingStorage.temporaryCompressedPath(for: relativePath))
        do {
            try storage.prepareFolder(for: relativePath)
        } catch {
            throw MediaImportError.fileFailed(error.localizedDescription)
        }

        let duration: TimeInterval
        do {
            switch kind {
            case .video:
                duration = try await extractor.extractAudio(from: source, to: temporary)
            case .audio:
                try files.copyItem(at: source, to: temporary)
                guard let measured = await durations.duration(of: temporary) else { throw MediaImportError.unplayable(name) }
                duration = measured
            }
            guard duration > 0 else { throw MediaImportError.unplayable(name) }
            try files.moveItem(at: temporary, to: destination)
        } catch {
            try? files.removeItem(at: temporary)
            Log.storage.error("가져오기 실패 \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            if let importError = error as? MediaImportError { throw importError }
            throw MediaImportError.fileFailed(error.localizedDescription)
        }

        let trimmedTitle = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let recording = Recording(
            title: trimmedTitle.isEmpty
                ? RecordingController.defaultTitle(subjectName: subject?.name ?? SubjectManager.unclassifiedName, startedAt: startedAt, calendar: calendar)
                : trimmedTitle,
            subject: subject,
            startedAt: startedAt,
            duration: duration,
            relativePath: relativePath
        )
        context.insert(recording)
        do {
            try context.save()
        } catch {
            context.rollback()
            try? files.removeItem(at: destination)
            throw MediaImportError.saveFailed(error.localizedDescription)
        }
        Log.storage.notice("가져옴: \(relativePath, privacy: .public)")
        return recording
    }
}
#endif
