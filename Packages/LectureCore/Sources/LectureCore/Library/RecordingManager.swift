#if canImport(SwiftData)
import Foundation
import Observation
import SwiftData

public enum RecordingManagerError: Error, Equatable, LocalizedError {
    case emptyTitle
    case fileMissing
    case exportFailed(String)
    case fileFailed(String)
    case saveFailed(String)

    public var errorDescription: String? {
        switch self {
        case .emptyTitle: "제목을 입력하세요."
        case .fileMissing: "녹음 파일을 찾을 수 없습니다."
        case .exportFailed(let reason): "녹음을 저장하지 못했습니다: \(reason)"
        case .fileFailed(let reason): "녹음 파일을 처리하지 못했습니다: \(reason)"
        case .saveFailed(let reason): "저장하지 못했습니다: \(reason)"
        }
    }
}

/// 녹음의 이름 변경·과목 이동·삭제를 맡는다. DB와 실제 파일 위치를 함께 바꾼다.
@MainActor
@Observable
public final class RecordingManager {
    public var errorMessage: String?

    private let context: ModelContext
    private let storage: RecordingStorage

    public init(context: ModelContext, storage: RecordingStorage) {
        self.context = context
        self.storage = storage
    }

    /// 제목만 바꾼다. 파일 이름은 그대로 둔다.
    public func rename(_ recording: Recording, to title: String) throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw fail(.emptyTitle) }
        let previous = recording.title
        recording.title = trimmed
        do {
            try context.save()
            errorMessage = nil
        } catch {
            recording.title = previous
            throw fail(.saveFailed(error.localizedDescription))
        }
    }

    /// 다른 과목(nil이면 미분류)으로 옮긴다. 파일을 먼저 옮기고, DB 저장이 실패하면 파일을 되돌린다.
    public func move(_ recording: Recording, to subject: Subject?) throws {
        guard recording.subject?.persistentModelID != subject?.persistentModelID else { return }
        let oldPath = recording.relativePath
        let baseName = ((oldPath as NSString).lastPathComponent as NSString).deletingPathExtension
        // 아직 압축 중인 CAF는 확장자를 그대로 둔다. m4a 이름을 붙이면 압축 흐름이 작업 파일로 알아보지 못한다.
        let newPath = storage.availableRelativePath(
            folder: RecordingStorage.folderPath(semester: subject?.semester, subjectName: subject?.name),
            baseName: baseName,
            fileExtension: (oldPath as NSString).pathExtension
        )
        do {
            try storage.moveFile(from: oldPath, to: newPath)
        } catch {
            Log.storage.error("녹음 이동 실패 \(oldPath, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw fail(.fileFailed(error.localizedDescription))
        }
        let oldSubject = recording.subject
        recording.subject = subject
        recording.relativePath = newPath
        do {
            try context.save()
            errorMessage = nil
        } catch {
            recording.subject = oldSubject
            recording.relativePath = oldPath
            try? storage.moveFile(from: newPath, to: oldPath)
            throw fail(.saveFailed(error.localizedDescription))
        }
    }

    /// 목록 줄에 보일 상태 (압축 중, 복구됨, 파일 없음).
    public func status(for recording: Recording) -> RecordingRowStatus {
        RecordingRowStatus(relativePath: recording.relativePath, isRecovered: recording.isRecovered, storage: storage)
    }

    /// 재생해도 되는지 확인한다. 파일이 없으면 안내를 `errorMessage`에 남기고 false.
    public func canPlay(_ recording: Recording) -> Bool {
        let playable = status(for: recording).isPlayable
        errorMessage = playable ? nil : RecordingRowStatus.missingFileNotice
        return playable
    }

    /// 녹음 파일의 실제 위치. Finder에서 보여 주거나 공유할 때 쓴다.
    public func fileURL(for recording: Recording) -> URL {
        storage.url(for: recording.relativePath)
    }

    /// macOS 공유 메뉴에 넘길 파일. 파일이 없으면 nil이라 공유 메뉴를 보이지 않는다.
    /// 어디에 올릴지는 사용자가 공유 메뉴에서 고르며, 앱이 먼저 올리는 일은 없다.
    public func shareURL(for recording: Recording) -> URL? {
        let url = fileURL(for: recording)
        return storage.fileExists(at: url) ? url : nil
    }

    /// "다른 곳에 저장…" 대화상자에 미리 채워 둘 파일 이름 (제목 + 확장자).
    public func suggestedExportName(for recording: Recording) -> String {
        let ext = (recording.relativePath as NSString).pathExtension
        let base = RecordingStorage.folderName(for: recording.title)
        return ext.isEmpty ? base : "\(base).\(ext)"
    }

    /// 녹음 파일을 `destination`으로 복사한다. 원본은 그대로 둔다.
    public func export(_ recording: Recording, to destination: URL) throws {
        let source = fileURL(for: recording)
        guard storage.fileExists(at: source) else { throw fail(.fileMissing) }
        do {
            try storage.copyFile(at: source, to: destination)
            errorMessage = nil
        } catch {
            Log.storage.error("녹음 내보내기 실패 \(recording.relativePath, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw fail(.exportFailed(error.localizedDescription))
        }
    }

    /// 파일을 영구 삭제하고 DB 기록도 지운다. 파일을 지우지 못하면 기록도 남겨 둔다.
    /// 너무 짧아 버리는 녹음처럼 되돌릴 필요가 없을 때 쓴다.
    public func delete(_ recording: Recording) throws {
        try remove(recording) { try storage.removeFile(at: $0) }
    }

    /// 파일을 휴지통으로 보내고 DB 기록을 지운다. 휴지통으로 보내지 못하면 파일도 기록도 그대로 둔다.
    /// 휴지통에서 되돌린 파일은 폴더 다시 읽기(3-35)로 목록에 되살릴 수 있다.
    public func trash(_ recording: Recording) throws {
        try remove(recording) { try storage.trashFile(at: $0) }
    }

    private func remove(_ recording: Recording, removingFile: (String) throws -> Void) throws {
        do {
            try removingFile(recording.relativePath)
        } catch {
            Log.storage.error("녹음 삭제 실패 \(recording.relativePath, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw fail(.fileFailed(error.localizedDescription))
        }
        context.delete(recording)
        do {
            try context.save()
            errorMessage = nil
        } catch {
            throw fail(.saveFailed(error.localizedDescription))
        }
    }

    private func fail(_ error: RecordingManagerError) -> RecordingManagerError {
        errorMessage = error.errorDescription
        return error
    }
}
#endif
