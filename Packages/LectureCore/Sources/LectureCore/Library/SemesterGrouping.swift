import Foundation

/// 사이드바 "과목"을 학기별로 묶는 순수 로직. SwiftData에 기대지 않아 단독으로 테스트한다.
public enum SemesterGrouping {
    /// 묶을 과목 한 개. `hasSchedule`은 시간표 칸이 하나라도 있는지.
    public struct Input: Equatable, Sendable {
        public var name: String
        public var semester: String
        public var hasSchedule: Bool

        public init(name: String, semester: String, hasSchedule: Bool) {
            self.name = name
            self.semester = semester
            self.hasSchedule = hasSchedule
        }
    }

    /// 학기 한 묶음. `indices`는 입력 배열에서 이 학기에 속한 과목의 위치 (입력 순서 그대로).
    public struct Section: Equatable, Identifiable, Sendable {
        /// 학기 이름. 학기가 비어 있는 과목의 묶음은 빈 문자열.
        public var semester: String
        public var indices: [Int]
        public var isCurrent: Bool

        public var id: String { semester }
        public var isOther: Bool { semester.isEmpty }
        /// 화면에 보일 이름.
        public var title: String { isOther ? SemesterGrouping.otherTitle : semester }
    }

    public static let otherTitle = "기타"

    /// 최신 학기가 위, "기타"가 맨 아래. 현재 학기는 시간표 칸이 있는 과목들의 학기 중 가장 최근 것이고,
    /// 시간표가 있는 과목이 없으면 가장 최근 학기다. 학기가 하나도 없으면 현재 학기는 없다.
    public static func sections(for inputs: [Input]) -> [Section] {
        var bySemester: [String: [Int]] = [:]
        for (index, input) in inputs.enumerated() {
            bySemester[normalized(input.semester), default: []].append(index)
        }
        let named = bySemester.keys.filter { !$0.isEmpty }.sorted(by: isNewer)
        let scheduled = named.filter { semester in bySemester[semester, default: []].contains { inputs[$0].hasSchedule } }
        let current = scheduled.first ?? named.first

        var result = named.map { Section(semester: $0, indices: bySemester[$0, default: []], isCurrent: $0 == current) }
        if let other = bySemester[""] {
            result.append(Section(semester: "", indices: other, isCurrent: false))
        }
        return result
    }

    /// 학기 제목을 보일 필요가 없는 경우 (학기가 정해진 과목이 하나도 없음).
    public static func showsHeaders(_ sections: [Section]) -> Bool {
        sections.contains { !$0.isOther }
    }

    static func normalized(_ semester: String) -> String {
        semester.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 연도와 학기 숫자("2026년 2학기" → 2026, 2)로 새 것을 앞에 둔다. 읽지 못하는 이름은 뒤로, 이름 순서로 정한다.
    static func isNewer(_ lhs: String, _ rhs: String) -> Bool {
        let (l, r) = (key(lhs), key(rhs))
        if l.year != r.year { return l.year > r.year }
        if l.term != r.term { return l.term > r.term }
        return lhs > rhs
    }

    private static func key(_ semester: String) -> (year: Int, term: Int) {
        guard let yearRange = semester.range(of: #"\d{4}"#, options: .regularExpression),
              let year = Int(semester[yearRange]) else { return (-1, 0) }
        let rest = semester[yearRange.upperBound...]
        let term = rest.range(of: #"\d"#, options: .regularExpression).flatMap { Int(rest[$0]) } ?? 0
        return (year, term)
    }
}

/// 사이드바 학기 묶음의 펼침 상태. 기본은 현재 학기와 "기타"가 펼쳐지고 지난 학기는 접힘이며,
/// 사용자가 바꾼 것만 기억한다 (새 학기가 생겨 "현재"가 바뀌어도 직접 바꾼 선택은 유지).
public struct SemesterExpansion: Equatable, Sendable {
    private var overrides: [String: Bool] = [:]

    public init() {}

    /// 저장해 둔 문자열(JSON)에서 읽는다. 비었거나 깨졌으면 기본 상태.
    public init(json: String) {
        if let data = json.data(using: .utf8), let decoded = try? JSONDecoder().decode([String: Bool].self, from: data) {
            overrides = decoded
        }
    }

    public var json: String {
        guard let data = try? JSONEncoder().encode(overrides) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    public func isExpanded(_ section: SemesterGrouping.Section) -> Bool {
        overrides[section.semester] ?? (section.isCurrent || section.isOther)
    }

    public mutating func set(_ expanded: Bool, for section: SemesterGrouping.Section) {
        overrides[section.semester] = expanded
    }
}
