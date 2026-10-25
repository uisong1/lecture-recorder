#if canImport(SwiftData)
import Foundation
import SwiftData
import Testing
@testable import LectureCore

@MainActor
@Suite struct ScheduleManagerTests {
    let container: ModelContainer
    let subjects: SubjectManager
    let manager: ScheduleManager

    init() throws {
        container = try LectureModelContainer.make(inMemory: true)
        subjects = SubjectManager(context: container.mainContext)
        manager = ScheduleManager(context: container.mainContext)
    }

    @Test func 과목에_요일과_시간을_추가한다() throws {
        let subject = try subjects.add(name: "자료구조", color: .green)
        try manager.add(subject: subject, weekday: .wednesday, start: TimeOfDay(hour: 13), end: TimeOfDay(hour: 14, minute: 15))
        try manager.add(subject: subject, weekday: .monday, start: TimeOfDay(hour: 13), end: TimeOfDay(hour: 14, minute: 15))
        #expect(manager.slots.map { $0.period?.weekday } == [.monday, .wednesday])
        #expect(subject.timeSlots.count == 2)
    }

    @Test func 과목을_고르지_않으면_거부된다() throws {
        #expect(throws: ScheduleEditError.noSubject) {
            try manager.add(subject: nil, weekday: .monday, start: TimeOfDay(hour: 9), end: TimeOfDay(hour: 10))
        }
    }

    @Test func 끝이_시작보다_빠르면_거부된다() throws {
        let subject = try subjects.add(name: "자료구조", color: .green)
        #expect(throws: ScheduleEditError.invalidTime) {
            try manager.add(subject: subject, weekday: .monday, start: TimeOfDay(hour: 10), end: TimeOfDay(hour: 9))
        }
    }

    @Test func 겹치면_거부되고_오류_문구가_보인다() throws {
        let ds = try subjects.add(name: "자료구조", color: .green)
        let os = try subjects.add(name: "운영체제", color: .red)
        try manager.add(subject: ds, weekday: .monday, start: TimeOfDay(hour: 10), end: TimeOfDay(hour: 11, minute: 30))

        manager.draftSubject = os
        manager.draftWeekday = .monday
        manager.draftStart = try TimeOfDay(hour: 11)
        manager.draftEnd = try TimeOfDay(hour: 12)
        manager.addDraft()

        #expect(manager.slots.count == 1)
        #expect(manager.errorMessage == "월 10:00–11:30 ‘자료구조’ 수업과 시간이 겹칩니다.")
    }

    @Test func 칸을_삭제한다() throws {
        let subject = try subjects.add(name: "자료구조", color: .green)
        let slot = try manager.add(subject: subject, weekday: .monday, start: TimeOfDay(hour: 9), end: TimeOfDay(hour: 10))
        try manager.delete(slot)
        #expect(manager.slots.isEmpty)
    }

    @Test func 저장된_칸으로_현재_과목을_찾는다() throws {
        let subject = try subjects.add(name: "자료구조", color: .green)
        try manager.add(subject: subject, weekday: .monday, start: TimeOfDay(hour: 10), end: TimeOfDay(hour: 11))
        let result = manager.schedule().classify(at: date(2026, 3, 2, 10, 30), calendar: seoulCalendar)
        #expect(result == .subject(subject.persistentModelID))
    }

    @Test func 과목을_지우면_시간표에서도_빠진다() throws {
        let subject = try subjects.add(name: "자료구조", color: .green)
        try manager.add(subject: subject, weekday: .monday, start: TimeOfDay(hour: 10), end: TimeOfDay(hour: 11))
        manager.draftSubject = subject
        try subjects.delete(subject)
        manager.reload()
        #expect(manager.slots.isEmpty)
        #expect(manager.draftSubject == nil)
    }
}
#endif
