import Foundation

/// 목록에서 볼 기간.
public enum RecordingPeriod: CaseIterable, Sendable {
    case all
    case last7Days
    case last30Days

    public var label: String {
        switch self {
        case .all: "전체"
        case .last7Days: "최근 7일"
        case .last30Days: "최근 30일"
        }
    }

    /// 오늘을 포함한 일수. 전체는 nil.
    var days: Int? {
        switch self {
        case .all: nil
        case .last7Days: 7
        case .last30Days: 30
        }
    }
}

/// 녹음 목록의 정렬 방향. 날짜(녹음 시작 시각) 기준이다.
public enum RecordingSortOrder: String, CaseIterable, Sendable {
    case newestFirst
    case oldestFirst

    public var label: String {
        switch self {
        case .newestFirst: "최신순"
        case .oldestFirst: "오래된 순"
        }
    }
}

/// 제목 검색과 기간으로 녹음을 거르는 조건. 화면과 DB를 모르는 순수 로직이다.
public struct RecordingFilter: Equatable, Sendable {
    public var query: String
    public var period: RecordingPeriod
    /// true면 아직 안 들은 녹음만 남긴다.
    public var unplayedOnly: Bool

    public init(query: String = "", period: RecordingPeriod = .all, unplayedOnly: Bool = false) {
        self.query = query
        self.period = period
        self.unplayedOnly = unplayedOnly
    }

    /// 걸러지는 조건이 하나라도 있는가.
    public var isActive: Bool { !normalizedQuery.isEmpty || period != .all || unplayedOnly }

    /// 앞뒤 공백을 떼고 한글 조합 방식을 맞춘 검색어.
    private var normalizedQuery: String {
        Self.normalize(query)
    }

    /// 제목과 시작 시각이 조건에 맞는지. `now`와 `calendar`는 기간 계산에만 쓴다.
    /// `isUnplayed`는 "안 들은 것만" 조건이 켜져 있을 때만 본다.
    public func matches(title: String, startedAt: Date, isUnplayed: Bool = false, now: Date, calendar: Calendar) -> Bool {
        matchesQuery(title) && matchesPeriod(startedAt, now: now, calendar: calendar) && (!unplayedOnly || isUnplayed)
    }

    /// 북마크용: 녹음 제목이나 북마크 메모 중 하나라도 검색어를 담으면 맞는다. 기간은 녹음 시작 시각으로 본다.
    public func matches(title: String, note: String, startedAt: Date, now: Date, calendar: Calendar) -> Bool {
        (matchesQuery(title) || matchesQuery(note)) && matchesPeriod(startedAt, now: now, calendar: calendar)
    }

    private func matchesQuery(_ title: String) -> Bool {
        let query = normalizedQuery
        if query.isEmpty { return true }
        return Self.normalize(title).range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    /// 오늘을 포함해 `days`일. 7일이면 오늘과 그 전 6일의 0시부터. 미래 시각은 포함한다.
    private func matchesPeriod(_ startedAt: Date, now: Date, calendar: Calendar) -> Bool {
        guard let days = period.days else { return true }
        let today = calendar.startOfDay(for: now)
        guard let cutoff = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return true }
        return startedAt >= cutoff
    }

    private static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
    }
}
