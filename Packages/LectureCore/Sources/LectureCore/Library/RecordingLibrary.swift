#if canImport(SwiftData)
import Foundation
import Observation
import SwiftData

/// 사이드바에서 고를 수 있는 분류.
public enum LibrarySelection: Hashable, Sendable {
    /// 과목과 상관없이 모든 녹음.
    case all
    case subject(PersistentIdentifier)
    case unclassified
}

/// 북마크 모아보기의 한 줄: 북마크와 그것이 속한 녹음.
public struct BookmarkEntry: Identifiable {
    public let bookmark: Bookmark
    public let recording: Recording
    public var id: PersistentIdentifier { bookmark.persistentModelID }
}

/// 과목별 녹음 목록을 보여주는 뷰모델.
@MainActor
@Observable
public final class RecordingLibrary {
    public private(set) var subjects: [Subject] = []
    /// 고른 분류의 녹음. `sortOrder` 순서.
    public private(set) var recordings: [Recording] = []
    public private(set) var selection: LibrarySelection?
    public var errorMessage: String?
    /// 제목 검색어와 기간. 바꾸면 목록이 바로 다시 걸러진다.
    public var filter = RecordingFilter() {
        didSet { recordings = filtered(by: selection) }
    }

    /// 목록 정렬 방향. 바꾸면 목록이 바로 다시 정렬되고 다음 실행에도 기억한다.
    public var sortOrder: RecordingSortOrder = .newestFirst {
        didSet {
            defaults.set(sortOrder.rawValue, forKey: Self.sortOrderKey)
            recordings = filtered(by: selection)
        }
    }

    static let sortOrderKey = "recordingSortOrder"

    private var all: [Recording] = []
    private let context: ModelContext
    private let now: @MainActor () -> Date
    private let calendar: Calendar
    private let defaults: UserDefaults

    public init(
        context: ModelContext,
        now: @escaping @MainActor () -> Date = { Date() },
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard
    ) {
        self.context = context
        self.now = now
        self.calendar = calendar
        self.defaults = defaults
        sortOrder = defaults.string(forKey: Self.sortOrderKey).flatMap(RecordingSortOrder.init(rawValue:)) ?? .newestFirst
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

    /// 분류에 들어 있는 녹음 수. 검색·기간 조건과 상관없는 전체 수다.
    public func count(for selection: LibrarySelection) -> Int {
        inCategory(selection).count
    }

    /// 고른 분류의 북마크를 모아 본 목록. 최근 녹음부터, 같은 녹음 안에서는 시점 순서다.
    /// 북마크가 없는 녹음은 나오지 않는다. 검색어는 녹음 제목과 북마크 메모를 함께 찾고 기간은 녹음 날짜 기준이다.
    public var bookmarkEntries: [BookmarkEntry] {
        let current = now()
        return inCategory(selection).flatMap { recording in
            recording.sortedBookmarks
                .filter { filter.matches(title: recording.title, note: $0.note, startedAt: recording.startedAt, now: current, calendar: calendar) }
                .map { BookmarkEntry(bookmark: $0, recording: recording) }
        }
    }

    /// 분류에 있는 북마크 수. 검색·기간 조건과 상관없는 전체 수다.
    public func bookmarkCount(for selection: LibrarySelection) -> Int {
        inCategory(selection).reduce(0) { $0 + $1.bookmarks.count }
    }

    /// 목록 행에 과목 이름을 함께 보여야 하는지. "모든 녹음"에서는 어느 과목인지 알 수 있어야 한다.
    public var showsSubjectName: Bool { selection == .all }

    /// 행에 보일 과목 이름. 과목이 없으면 "미분류".
    public func subjectName(of recording: Recording) -> String {
        recording.subject?.name ?? SubjectManager.unclassifiedName
    }

    private func inCategory(_ selection: LibrarySelection?) -> [Recording] {
        switch selection {
        case nil: []
        case .all: all
        case .unclassified: all.filter { $0.subject == nil }
        case .subject(let id): all.filter { $0.subject?.persistentModelID == id }
        }
    }

    private func filtered(by selection: LibrarySelection?) -> [Recording] {
        let current = now()
        let matching = inCategory(selection).filter {
            filter.matches(title: $0.title, startedAt: $0.startedAt, isUnplayed: $0.isUnplayed, now: current, calendar: calendar)
        }
        // `all`은 최신순으로 읽어 오므로 오래된 순일 때만 뒤집는다.
        return sortOrder == .oldestFirst ? Array(matching.reversed()) : matching
    }
}
#endif
