#if canImport(SwiftData)
import Foundation
import SwiftData

public enum TimetableImportError: Error, Equatable, LocalizedError {
    /// 초안에 고쳐야 할 문제가 남아 있음. 아무것도 저장하지 않았다.
    case invalid([TimetableDraftEditor.Issue])
    case saveFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalid(let issues): issues.first?.message ?? "시간표를 확인해 주세요."
        case .saveFailed(let reason): "시간표를 저장하지 못했습니다: \(reason)"
        }
    }
}

/// 가져오기가 만든 것과 바꾼 것.
public struct TimetableImportResult: Equatable, Sendable {
    public let semester: String
    public let createdSubjects: [String]
    public let reusedSubjects: [String]
    public let slotCount: Int
    /// 새로 가져오면서 지운 기존 시간표 칸 수.
    public let removedSlotCount: Int
}

/// 확인된 시간표 초안을 과목과 시간표 칸으로 저장한다.
/// 기존 시간표 칸은 모두 지우고 초안의 칸으로 바꾼다 (과목과 녹음은 그대로 둔다).
/// 이름이 같은 과목(대소문자 무시)은 새로 만들지 않고 다시 쓰며 학기만 바꾼다.
@MainActor
public final class TimetableImporter {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// 가져오면 지워질 기존 시간표 칸 수. 확인 창에서 알려 주는 데 쓴다.
    public func existingSlotCount() -> Int {
        (try? context.fetchCount(FetchDescriptor<TimeSlot>())) ?? 0
    }

    @discardableResult
    public func apply(_ editor: TimetableDraftEditor) throws(TimetableImportError) -> TimetableImportResult {
        let issues = editor.issues
        guard issues.isEmpty else { throw .invalid(issues) }
        let semester = editor.semesterName

        let existingSubjects: [Subject]
        let existingSlots: [TimeSlot]
        do {
            existingSubjects = try context.fetch(FetchDescriptor<Subject>())
            existingSlots = try context.fetch(FetchDescriptor<TimeSlot>())
        } catch {
            throw .saveFailed(error.localizedDescription)
        }

        for slot in existingSlots { context.delete(slot) }

        // 이름(대소문자 무시)으로 과목을 찾고 없으면 만든다.
        var byName: [String: Subject] = [:]
        for subject in existingSubjects { byName[Self.key(subject.name)] = subject }
        var created: [String] = []
        var reused: [String] = []
        var createdKeys = Set<String>()
        let palette = SubjectColor.allCases.filter { $0 != .gray }
        func subject(named rawName: String) -> Subject {
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            if let found = byName[Self.key(name)] {
                found.semester = semester
                // 이번에 새로 만든 과목을 같은 가져오기의 다음 줄에서 다시 찾은 것은 다시 쓴 것이 아니다.
                if !createdKeys.contains(Self.key(name)), !reused.contains(found.name) { reused.append(found.name) }
                return found
            }
            let color = palette[(existingSubjects.count + created.count) % palette.count]
            let newSubject = Subject(name: name, color: color)
            newSubject.semester = semester
            context.insert(newSubject)
            byName[Self.key(name)] = newSubject
            createdKeys.insert(Self.key(name))
            created.append(name)
            return newSubject
        }

        var slotCount = 0
        for row in editor.includedRows {
            guard let period = try? ClassPeriod(weekday: row.weekday, start: row.start, end: row.end) else { continue }
            context.insert(TimeSlot(period, subject: subject(named: row.name)))
            slotCount += 1
        }
        for name in editor.cleanedUntimedSubjects { _ = subject(named: name) }

        do {
            try context.save()
        } catch {
            Log.data.error("시간표 가져오기 저장 실패: \(error.localizedDescription, privacy: .public)")
            context.rollback()
            throw .saveFailed(error.localizedDescription)
        }
        return TimetableImportResult(
            semester: semester,
            createdSubjects: created,
            reusedSubjects: reused,
            slotCount: slotCount,
            removedSlotCount: existingSlots.count
        )
    }

    private static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
#endif
