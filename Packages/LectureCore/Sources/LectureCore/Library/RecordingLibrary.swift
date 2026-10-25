#if canImport(SwiftData)
import Foundation
import Observation
import SwiftData

/// 사이드바에서 고를 수 있는 분류.
public enum LibrarySelection: Hashable, Sendable {
    case subject(PersistentIdentifier)
    case unclassified
}

/// 과목별 녹음 목록을 보여주는 뷰모델.
@MainActor
@Observable
public final class RecordingLibrary {
    public private(set) var subjects: [Subject] = []
    /// 고른 분류의 녹음. 최신순.
    public private(set) var recordings: [Recording] = []
    public private(set) var selection: LibrarySelection?
    public var errorMessage: String?

    private var all: [Recording] = []
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
        reload()
    }

    /// DB에서 과목과 녹음을 다시 읽는다.
    public func reload() {
        do {
            subjects = try context.fetch(FetchDescriptor<Subject>(sortBy: [SortDescriptor(\.name)]))
            all = try context.fetch(FetchDescriptor<Recording>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)]))
            errorMessage = nil
        } catch {
            Log.data.error("녹음 목록을 불러오지 못함: \(error.localizedDescription, privacy: .public)")
            errorMessage = "녹음 목록을 불러오지 못했습니다."
            subjects = []
            all = []
        }
        // 삭제된 과목을 고르고 있었다면 선택을 푼다.
        if case .subject(let id) = selection, !subjects.contains(where: { $0.persistentModelID == id }) {
            selection = nil
        }
        recordings = filtered(by: selection)
    }

    public func select(_ selection: LibrarySelection?) {
        self.selection = selection
        recordings = filtered(by: selection)
    }

    /// 분류에 들어 있는 녹음 수.
    public func count(for selection: LibrarySelection) -> Int {
        filtered(by: selection).count
    }

    private func filtered(by selection: LibrarySelection?) -> [Recording] {
        switch selection {
        case nil: []
        case .unclassified: all.filter { $0.subject == nil }
        case .subject(let id): all.filter { $0.subject?.persistentModelID == id }
        }
    }
}
#endif
