import Foundation

/// 미리보기 표에서 사용자가 시간표 초안을 고치는 동작. 확인하기 전에는 아무것도 저장하지 않는다.
/// 줄은 위치(index)로 가리킨다. 범위 밖 위치는 무시한다.
public struct TimetableDraftEditor: Equatable, Sendable {
    public var draft: TimetableDraft

    public init(draft: TimetableDraft) {
        self.draft = draft
    }

    /// 저장 전에 고쳐야 할 문제. 저장 대상이 아닌 줄의 문제는 세지 않는다.
    public enum Issue: Equatable, Sendable {
        case emptySemester
        case emptyName(row: Int)
        case reservedName(row: Int)
        case timeOrder(row: Int)
        /// `row`가 더 앞 줄 `with`와 같은 요일에 시간이 겹친다.
        case overlap(row: Int, with: Int)

        /// 화면에 보일 한국어 문구. 줄 번호는 1부터 센다.
        public var message: String {
            switch self {
            case .emptySemester: "학기 이름을 입력하세요."
            case .emptyName(let row): "\(row + 1)번째 줄의 과목 이름이 비어 있습니다."
            case .reservedName(let row): "\(row + 1)번째 줄: ‘\(Self.unclassified)’는 과목 이름으로 쓸 수 없습니다."
            case .timeOrder(let row): "\(row + 1)번째 줄: 끝나는 시각은 시작 시각보다 늦어야 합니다."
            case let .overlap(row, other): "\(other + 1)번째 줄과 \(row + 1)번째 줄의 시간이 겹칩니다."
            }
        }

        static let unclassified = "미분류"
    }

    // MARK: 문제 찾기

    public var issues: [Issue] {
        var result: [Issue] = []
        if semesterName.isEmpty { result.append(.emptySemester) }
        let rows = draft.rows
        for (index, row) in rows.enumerated() where row.include {
            let name = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty {
                result.append(.emptyName(row: index))
            } else if name == Issue.unclassified {
                result.append(.reservedName(row: index))
            }
            if row.end <= row.start { result.append(.timeOrder(row: index)) }
        }
        for (index, row) in rows.enumerated() where row.include && row.start < row.end {
            guard let earlier = rows[..<index].indices.first(where: { other in
                let candidate = rows[other]
                return candidate.include && candidate.weekday == row.weekday && candidate.start < candidate.end
                    && candidate.start < row.end && row.start < candidate.end
            }) else { continue }
            result.append(.overlap(row: index, with: earlier))
        }
        return result
    }

    public var isValid: Bool { issues.isEmpty }

    /// 앞뒤 공백을 뗀 학기 이름.
    public var semesterName: String {
        (draft.semester ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 저장 대상 줄.
    public var includedRows: [TimetableRow] { draft.rows.filter(\.include) }

    /// 폴더만 만들 과목 이름. 빈 이름은 빼고 같은 이름(대소문자 무시)은 한 번만 쓴다.
    public var cleanedUntimedSubjects: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in draft.untimedSubjects {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name != Issue.unclassified, seen.insert(name.lowercased()).inserted else { continue }
            result.append(name)
        }
        return result
    }

    // MARK: 줄 고치기

    public mutating func setSemester(_ name: String) {
        draft.semester = name
    }

    public mutating func setName(_ name: String, at index: Int) {
        guard draft.rows.indices.contains(index) else { return }
        draft.rows[index].name = name
    }

    public mutating func setWeekday(_ weekday: Weekday, at index: Int) {
        guard draft.rows.indices.contains(index) else { return }
        draft.rows[index].weekday = weekday
    }

    public mutating func setStart(_ start: TimeOfDay, at index: Int) {
        guard draft.rows.indices.contains(index) else { return }
        draft.rows[index].start = start
    }

    public mutating func setEnd(_ end: TimeOfDay, at index: Int) {
        guard draft.rows.indices.contains(index) else { return }
        draft.rows[index].end = end
    }

    public mutating func setInclude(_ include: Bool, at index: Int) {
        guard draft.rows.indices.contains(index) else { return }
        draft.rows[index].include = include
    }

    /// 맨 아래에 빈 줄을 더한다 (월 09:00~10:15, 저장 대상). 더한 줄의 위치를 돌려준다.
    @discardableResult
    public mutating func addRow() -> Int {
        let start = (try? TimeOfDay(hour: 9)) ?? .midnight
        let end = (try? TimeOfDay(hour: 10, minute: 15)) ?? .midnight
        draft.rows.append(TimetableRow(name: "", weekday: .monday, start: start, end: end, hasRoom: true, include: true))
        return draft.rows.count - 1
    }

    public mutating func deleteRow(at index: Int) {
        guard draft.rows.indices.contains(index) else { return }
        draft.rows.remove(at: index)
    }

    // MARK: 시간 없는 과목

    public mutating func addUntimedSubject(_ name: String = "") {
        draft.untimedSubjects.append(name)
    }

    public mutating func renameUntimedSubject(at index: Int, to name: String) {
        guard draft.untimedSubjects.indices.contains(index) else { return }
        draft.untimedSubjects[index] = name
    }

    public mutating func removeUntimedSubject(at index: Int) {
        guard draft.untimedSubjects.indices.contains(index) else { return }
        draft.untimedSubjects.remove(at: index)
    }
}
