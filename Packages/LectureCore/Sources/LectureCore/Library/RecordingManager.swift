#if canImport(SwiftData)
import Foundation
import Observation
import SwiftData

public enum RecordingManagerError: Error, Equatable, LocalizedError {
    case emptyTitle
    case fileFailed(String)
    case saveFailed(String)

    public var errorDescription: String? {
        switch self {
        case .emptyTitle: "제목을 입력하세요."
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
        let newPath = storage.availableRelativePath(folder: RecordingStorage.folderName(for: subject?.name), baseName: baseName)
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

    /// 파일과 DB 기록을 모두 지운다. 파일을 지우지 못하면 기록도 남겨 둔다.
    public func delete(_ recording: Recording) throws {
        do {
            try storage.removeFile(at: recording.relativePath)
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
