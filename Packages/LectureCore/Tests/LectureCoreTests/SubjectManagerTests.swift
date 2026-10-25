#if canImport(SwiftData)
import Foundation
import SwiftData
import Testing
@testable import LectureCore

@MainActor
@Suite struct SubjectManagerTests {
    let container: ModelContainer
    let manager: SubjectManager

    init() throws {
        container = try LectureModelContainer.make(inMemory: true)
        manager = SubjectManager(context: container.mainContext)
    }

    @Test func 과목을_추가하면_이름순으로_보인다() throws {
        try manager.add(name: "운영체제", color: .red)
        try manager.add(name: "  자료구조 ", color: .green)
        #expect(manager.subjects.map(\.name) == ["운영체제", "자료구조"])
        #expect(manager.subjects.last?.color == .green)
    }

    @Test func 빈_이름은_거부된다() {
        #expect(throws: SubjectError.emptyName) { try manager.add(name: "   ", color: .red) }
        #expect(manager.subjects.isEmpty)
    }

    @Test func 같은_이름은_거부된다() throws {
        try manager.add(name: "Calculus", color: .red)
        #expect(throws: SubjectError.duplicateName("calculus")) { try manager.add(name: "calculus", color: .blue) }
    }

    @Test func 미분류는_과목_이름으로_쓸_수_없다() {
        #expect(throws: SubjectError.reservedName("미분류")) { try manager.add(name: "미분류", color: .gray) }
    }

    @Test func 이름을_바꾼다() throws {
        let subject = try manager.add(name: "자료구조", color: .red)
        try manager.rename(subject, to: "자료구조론")
        #expect(manager.subjects.map(\.name) == ["자료구조론"])
    }

    @Test func 다른_과목_이름으로는_바꿀_수_없다() throws {
        try manager.add(name: "운영체제", color: .red)
        let subject = try manager.add(name: "자료구조", color: .red)
        #expect(throws: SubjectError.duplicateName("운영체제")) { try manager.rename(subject, to: "운영체제") }
        #expect(subject.name == "자료구조")
    }

    @Test func 자기_이름으로_바꾸는_것은_허용된다() throws {
        let subject = try manager.add(name: "자료구조", color: .red)
        try manager.rename(subject, to: "자료구조")
        #expect(subject.name == "자료구조")
    }

    @Test func 과목을_삭제한다() throws {
        let subject = try manager.add(name: "자료구조", color: .red)
        try manager.delete(subject)
        #expect(manager.subjects.isEmpty)
    }

    @Test func 입력란으로_추가하고_실패하면_오류_문구를_남긴다() {
        manager.draftName = "선형대수"
        manager.draftColor = .purple
        manager.addDraft()
        #expect(manager.subjects.map(\.name) == ["선형대수"])
        #expect(manager.draftName.isEmpty)
        #expect(manager.errorMessage == nil)

        manager.draftName = "선형대수"
        manager.addDraft()
        #expect(manager.errorMessage == "‘선형대수’ 과목이 이미 있습니다.")
        #expect(manager.draftName == "선형대수")
    }

    @Test func 앱을_다시_켜도_과목이_유지된다() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "test.store")

        do {
            // ModelContext는 컨테이너를 붙잡지 않으므로 컨테이너를 변수로 들고 있어야 한다.
            let firstContainer = try LectureModelContainer.make(url: url)
            let first = SubjectManager(context: firstContainer.mainContext)
            let subject = try first.add(name: "자료구조", color: .green)
            try first.add(name: "운영체제", color: .red)
            try first.rename(subject, to: "자료구조론")
        }

        let secondContainer = try LectureModelContainer.make(url: url)
        let second = SubjectManager(context: secondContainer.mainContext)
        #expect(second.subjects.map(\.name) == ["운영체제", "자료구조론"])
        #expect(second.subjects.last?.color == .green)
    }
}
#endif
