#if canImport(SwiftData)
import Foundation
import Observation
import SwiftData

public enum BookmarkError: Error, Equatable, LocalizedError {
    case saveFailed(String)

    public var errorDescription: String? {
        switch self {
        case .saveFailed(let reason): "북마크를 저장하지 못했습니다: \(reason)"
        }
    }
}

/// 북마크 추가·메모 수정·삭제를 맡는다.
@MainActor
@Observable
public final class BookmarkManager {
    public var errorMessage: String?

    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// 녹음의 `time`초 지점에 북마크를 만든다. 0보다 작으면 0으로 맞춘다.
    @discardableResult
    public func add(to recording: Recording, at time: TimeInterval, note: String = "", now: Date) throws -> Bookmark {
        let bookmark = Bookmark(time: max(time, 0), note: note, createdAt: now, recording: recording)
        context.insert(bookmark)
        do {
            try save()
        } catch {
            context.delete(bookmark)
            throw error
        }
        return bookmark
    }

    public func updateNote(_ bookmark: Bookmark, to note: String) throws {
        let previous = bookmark.note
        bookmark.note = note
        do {
            try save()
        } catch {
            bookmark.note = previous
            throw error
        }
    }

    public func delete(_ bookmark: Bookmark) throws {
        context.delete(bookmark)
        try save()
    }

    private func save() throws {
        do {
            try context.save()
            errorMessage = nil
        } catch {
            Log.data.error("북마크 저장 실패: \(error.localizedDescription, privacy: .public)")
            let failure = BookmarkError.saveFailed(error.localizedDescription)
            errorMessage = failure.errorDescription
            throw failure
        }
    }
}
#endif
