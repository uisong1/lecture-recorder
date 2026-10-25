#if canImport(SwiftData)
import Foundation
import Observation
import SwiftData

public enum ScheduleEditError: Error, Equatable, LocalizedError {
    case noSubject
    case invalidTime
    case overlaps(subjectName: String, period: ClassPeriod)
    case saveFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noSubject: "과목을 먼저 고르세요."
        case .invalidTime: "끝나는 시각은 시작 시각보다 늦어야 합니다."
        case let .overlaps(subjectName, period):
            "\(period.weekday.shortName) \(period.start)–\(period.end) ‘\(subjectName)’ 수업과 시간이 겹칩니다."
        case .saveFailed(let reason): "저장하지 못했습니다: \(reason)"
        }
    }
}

/// 시간표 칸 추가·삭제를 맡는 뷰모델.
@MainActor
@Observable
public final class ScheduleManager {
    /// 요일 → 시작 순으로 정렬된 시간표 칸.
    public private(set) var slots: [TimeSlot] = [] {
        didSet { onChange?() }
    }
    /// 시간표 칸이 다시 읽힐 때마다 불린다 (수업 시작 알림 예약을 다시 만드는 데 쓴다).
    public var onChange: (@MainActor () -> Void)?
    public var errorMessage: String?

    /// 새 칸 입력란.
    public var draftSubject: Subject?
    public var draftWeekday: Weekday = .monday
    public var draftStart: TimeOfDay = (try? TimeOfDay(hour: 9)) ?? .midnight
    public var draftEnd: TimeOfDay = (try? TimeOfDay(hour: 10, minute: 15)) ?? .midnight

    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
        reload()
    }

    public func reload() {
        do {
            let all = try context.fetch(FetchDescriptor<TimeSlot>())
            slots = all
                .filter { $0.subject != nil && $0.period != nil }
                .sorted { lhs, rhs in
                    guard let l = lhs.period, let r = rhs.period else { return false }
                    return (l.weekday, l.start) < (r.weekday, r.start)
                }
        } catch {
            Log.data.error("시간표를 불러오지 못함: \(error.localizedDescription, privacy: .public)")
            errorMessage = "시간표를 불러오지 못했습니다."
        }
        if let subject = draftSubject, subject.isDeleted || subject.modelContext == nil {
            draftSubject = nil
        }
    }

    /// 저장된 칸으로 만든 시간표. 녹음을 과목에 분류할 때 쓴다.
    public func schedule() -> ClassSchedule<PersistentIdentifier> {
        ClassSchedule(entries: slots.compactMap { slot in
            guard let period = slot.period, let subject = slot.subject else { return nil }
            return .init(period: period, subjectID: subject.persistentModelID)
        })
    }

    @discardableResult
    public func add(subject: Subject?, weekday: Weekday, start: TimeOfDay, end: TimeOfDay) throws(ScheduleEditError) -> TimeSlot {
        guard let subject else { throw .noSubject }
        let period: ClassPeriod
        do {
            period = try ClassPeriod(weekday: weekday, start: start, end: end)
        } catch {
            throw .invalidTime
        }
        if let conflict = schedule().conflict(for: period) {
            let name = slots.first { $0.subject?.persistentModelID == conflict.subjectID }?.subject?.name ?? ""
            throw .overlaps(subjectName: name, period: conflict.period)
        }
        let slot = TimeSlot(period, subject: subject)
        context.insert(slot)
        try save()
        return slot
    }

    public func addDraft() {
        perform { try add(subject: draftSubject, weekday: draftWeekday, start: draftStart, end: draftEnd) }
    }

    public func delete(_ slot: TimeSlot) throws(ScheduleEditError) {
        context.delete(slot)
        try save()
    }

    public func perform(_ action: () throws -> Void) {
        do {
            try action()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() throws(ScheduleEditError) {
        do {
            try context.save()
        } catch {
            Log.data.error("시간표 저장 실패: \(error.localizedDescription, privacy: .public)")
            context.rollback()
            reload()
            throw .saveFailed(error.localizedDescription)
        }
        reload()
    }
}
#endif
