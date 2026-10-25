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
        didSet {
            recordings = filtered(by: selection)
            pruneSelection()
        }
    }

    /// 목록에서 ⌘클릭·Shift클릭으로 고른 녹음. 과목을 바꾸면 비워지고, 목록에서 사라진 녹음은 빠진다.
    public var selectedIDs: Set<PersistentIdentifier> = []

    /// 목록 정렬 방향. 바꾸면 목록이 바로 다시 정렬되고 다음 실행에도 기억한다.
    public var sortOrder: RecordingSortOrder = .newestFirst {
        didSet {
            defaults.set(sortOrder.rawValue, forKey: Self.sortOrderKey)
            recordings = filtered(by: selection)
            pruneSelection()
        }
    }

    static let sortOrderKey = "recordingSortOrder"
    static let semesterExpansionKey = "sidebarSemesterExpansion"

    /// 사이드바 과목의 학기 묶음. `reload`에서 한 번 계산한다.
    public private(set) var semesterSections: [SemesterGrouping.Section] = []

    /// 학기 묶음을 펼쳤는지. 바꾸면 다음 실행에도 기억한다.
    public private(set) var semesterExpansion = SemesterExpansion() {
        didSet { defaults.set(semesterExpansion.json, forKey: Self.semesterExpansionKey) }
    }

    private var all: [Recording] = []
    /// 분류마다 녹음 수. `reload`에서 한 번 세어 두고, 사이드바를 그릴 때마다 다시 세지 않는다.
    private var counts = Counts()
    /// 목록 행의 상태(파일 존재 확인) 결과. 보이는 행만 채워지고 `reload`에서 비운다.
    @ObservationIgnored private var statusCache: [PersistentIdentifier: (path: String, status: RecordingRowStatus)] = [:]

    private struct Counts {
        var all = 0
        var unclassified = 0
        var bySubject: [PersistentIdentifier: Int] = [:]
    }
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
        semesterExpansion = SemesterExpansion(json: defaults.string(forKey: Self.semesterExpansionKey) ?? "")
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
        counts = Self.count(all)
        semesterSections = SemesterGrouping.sections(for: subjects.map {
            SemesterGrouping.Input(name: $0.name, semester: $0.semester, hasSchedule: !$0.timeSlots.isEmpty)
        })
        statusCache = [:]
        recordings = filtered(by: selection)
        pruneSelection()
    }

    private static func count(_ recordings: [Recording]) -> Counts {
        var counts = Counts()
        counts.all = recordings.count
        for recording in recordings {
            if let id = recording.subject?.persistentModelID {
                counts.bySubject[id, default: 0] += 1
            } else {
                counts.unclassified += 1
            }
        }
        return counts
    }

    /// 학기 묶음에 속한 과목 (이름 순).
    public func subjects(in section: SemesterGrouping.Section) -> [Subject] {
        section.indices.compactMap { subjects.indices.contains($0) ? subjects[$0] : nil }
    }

    public func isExpanded(_ section: SemesterGrouping.Section) -> Bool {
        semesterExpansion.isExpanded(section)
    }

    public func setExpanded(_ expanded: Bool, for section: SemesterGrouping.Section) {
        semesterExpansion.set(expanded, for: section)
    }

    public func select(_ selection: LibrarySelection?) {
        self.selection = selection
        selectedIDs = []
        recordings = filtered(by: selection)
    }

    /// 고른 녹음. 목록 순서를 따른다.
    public var selectedRecordings: [Recording] {
        recordings.filter { selectedIDs.contains($0.persistentModelID) }
    }

    /// 둘 이상 골랐는가. 하나만 고른 것은 그냥 눌러 본 것이라 여러 건 동작의 대상으로 보지 않는다.
    public var isMultiSelecting: Bool { selectedRecordings.count > 1 }

    /// 내보낼 녹음: 둘 이상 골랐으면 그것만, 아니면 지금 목록 전체.
    public var exportRecordings: [Recording] {
        isMultiSelecting ? selectedRecordings : recordings
    }

    public func clearSelection() {
        selectedIDs = []
    }

    private func pruneSelection() {
        guard !selectedIDs.isEmpty else { return }
        let visible = Set(recordings.map(\.persistentModelID))
        selectedIDs.formIntersection(visible)
    }

    /// 분류에 들어 있는 녹음 수. 검색·기간 조건과 상관없는 전체 수다.
    /// `reload` 때 세어 둔 값이라, 녹음을 바꾼 뒤에는 `reload`를 불러야 맞게 갱신된다.
    public func count(for selection: LibrarySelection) -> Int {
        switch selection {
        case .all: counts.all
        case .unclassified: counts.unclassified
        case .subject(let id): counts.bySubject[id] ?? 0
        }
    }

    /// 목록 행에 보일 상태. 파일 존재 확인은 행이 처음 그려질 때 한 번만 하고 `reload`까지 같은 결과를 쓴다
    /// (경로가 바뀐 녹음은 다시 확인한다). 재생 가능 여부는 이 값이 아니라 `RecordingManager.canPlay`가 그때그때 확인한다.
    public func rowStatus(for recording: Recording, using manager: RecordingManager) -> RecordingRowStatus {
        let id = recording.persistentModelID
        if let cached = statusCache[id], cached.path == recording.relativePath { return cached.status }
        let status = manager.status(for: recording)
        statusCache[id] = (recording.relativePath, status)
        return status
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

    /// 지금 목록을 묶어 내보낼 때 쓸 이름: 고른 분류 + 기간 (예: "자료구조", "모든 녹음 최근 7일").
    public var exportLabel: String {
        if isMultiSelecting { return "선택한 녹음 \(selectedRecordings.count)개" }
        var name: String
        switch selection {
        case nil, .all: name = "모든 녹음"
        case .unclassified: name = SubjectManager.unclassifiedName
        case .subject(let id): name = subjects.first { $0.persistentModelID == id }?.name ?? "모든 녹음"
        }
        if filter.period != .all { name += " \(filter.periodLabel(calendar: calendar))" }
        return name
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
