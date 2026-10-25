#if canImport(SwiftData)
import Foundation
import Observation
import SwiftData

/// 사이드바에서 고른 분류.
public enum LibrarySelection: Hashable, Sendable {
    case unclassified
    case subject(PersistentIdentifier)
}

/// 과목별 녹음 목록을 보여주는 뷰모델. 녹음이 바뀌면 `reload()`를 불러야 한다.
@MainActor
@Observable
public final class RecordingLibrary {
    public var selection: LibrarySelection = .unclassified
    /// 고른 분류의 녹음. 최신순.
    public private(set) var recordings: [Recording] = []
    /// 분류별 녹음 개수. 사이드바에 보여준다.
    public private(set) var unclassifiedCount = 0
    public var errorMessage: String?

    private let context: ModelContext
    private var all: [Recording] = []

    public init(context: ModelContext) {
        self.context = context
        reload()
    }

    public func reload() {
        do {
            all = try context.fetch(FetchDescriptor<Recording>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)]))
            errorMessage = nil
        } catch {
            Log.data.error("녹음 목록을 불러오지 못함: \(error.localizedDescription, privacy: .public)")
            errorMessage = "녹음 목록을 불러오지 못했습니다."
            all = []
        }
        // 고른 과목이 지워졌으면 미분류로 돌아간다.
        if case .subject(let id) = selection, !subjectExists(id) { selection = .unclassified }
        unclassifiedCount = all.filter { $0.subject == nil }.count
        recordings = all.filter { matches($0, selection) }
    }

    /// 분류를 바꾸고 목록을 갱신한다.
    public func select(_ newSelection: LibrarySelection) {
        selection = newSelection
        recordings = all.filter { matches($0, newSelection) }
    }

    public func count(for subject: Subject) -> Int {
        all.filter { $0.subject?.persistentModelID == subject.persistentModelID }.count
    }

    private func subjectExists(_ id: PersistentIdentifier) -> Bool {
        let subjects = (try? context.fetch(FetchDescriptor<Subject>())) ?? []
        return subjects.contains { $0.persistentModelID == id }
    }

    private func matches(_ recording: Recording, _ selection: LibrarySelection) -> Bool {
        switch selection {
        case .unclassified: recording.subject == nil
        case .subject(let id): recording.subject?.persistentModelID == id
        }
    }
}
#endif
