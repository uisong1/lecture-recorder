#if canImport(SwiftData)
import Foundation
import Observation
import SwiftData

public enum SubjectError: Error, Equatable, LocalizedError {
    case emptyName
    case duplicateName(String)
    case reservedName(String)
    case saveFailed(String)

    public var errorDescription: String? {
        switch self {
        case .emptyName: "과목 이름을 입력하세요."
        case .duplicateName(let name): "‘\(name)’ 과목이 이미 있습니다."
        case .reservedName(let name): "‘\(name)’은(는) 과목 이름으로 쓸 수 없습니다."
        case .saveFailed(let reason): "저장하지 못했습니다: \(reason)"
        }
    }
}

/// 과목 추가·이름 변경·삭제를 맡는 뷰모델.
@MainActor
@Observable
public final class SubjectManager {
    /// 시간표가 없는 녹음이 들어가는 분류 이름. 과목 이름으로 쓸 수 없다.
    public static let unclassifiedName = "미분류"

    public private(set) var subjects: [Subject] = [] {
        didSet { onChange?() }
    }
    /// 과목 목록이 다시 읽힐 때마다 불린다 (수업 시작 알림 문구를 새로 만드는 데 쓴다).
    public var onChange: (@MainActor () -> Void)?
    /// 화면에 보여줄 마지막 오류.
    public var errorMessage: String?

    /// 새 과목 입력란.
    public var draftName = ""
    public var draftColor: SubjectColor = .blue

    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
        reload()
    }

    /// 처음 쓸 때 보여 줄 안내 문구. 과목을 등록하면 녹음이 시간표대로 분류된다는 것만 알린다.
    public static let firstRunGuideText = "과목과 시간표를 먼저 등록하면 녹음이 자동으로 분류돼요"

    /// 과목이 하나도 없으면 true. 시간표 없이도 녹음은 되므로 막지 않고 안내만 한다.
    public var needsFirstRunGuide: Bool { subjects.isEmpty }

    public func reload() {
        do {
            subjects = try context.fetch(FetchDescriptor<Subject>(sortBy: [SortDescriptor(\.name)]))
        } catch {
            Log.data.error("과목 목록을 불러오지 못함: \(error.localizedDescription, privacy: .public)")
            errorMessage = "과목 목록을 불러오지 못했습니다."
        }
    }

    @discardableResult
    public func add(name: String, color: SubjectColor) throws(SubjectError) -> Subject {
        let name = try validated(name, excluding: nil)
        let subject = Subject(name: name, color: color)
        context.insert(subject)
        try save()
        return subject
    }

    /// 입력란의 내용으로 과목을 추가한다. 실패하면 `errorMessage`에 남긴다.
    public func addDraft() {
        perform {
            try add(name: draftName, color: draftColor)
            draftName = ""
        }
    }

    public func rename(_ subject: Subject, to newName: String) throws(SubjectError) {
        let name = try validated(newName, excluding: subject)
        guard name != subject.name else { return }
        subject.name = name
        try save()
    }

    public func setColor(_ color: SubjectColor, for subject: Subject) throws(SubjectError) {
        subject.color = color
        try save()
    }

    /// 과목을 지운다. 시간표 칸은 함께 지워지고 녹음은 미분류로 남는다.
    public func delete(_ subject: Subject) throws(SubjectError) {
        context.delete(subject)
        try save()
    }

    /// 오류를 `errorMessage`로 바꿔 화면에 보여준다.
    public func perform(_ action: () throws -> Void) {
        do {
            try action()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func validated(_ rawName: String, excluding subject: Subject?) throws(SubjectError) -> String {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw .emptyName }
        guard name != Self.unclassifiedName else { throw .reservedName(name) }
        let isDuplicate = subjects.contains {
            $0 !== subject && $0.name.compare(name, options: [.caseInsensitive]) == .orderedSame
        }
        guard !isDuplicate else { throw .duplicateName(name) }
        return name
    }

    private func save() throws(SubjectError) {
        do {
            try context.save()
        } catch {
            Log.data.error("과목 저장 실패: \(error.localizedDescription, privacy: .public)")
            context.rollback()
            reload()
            throw .saveFailed(error.localizedDescription)
        }
        reload()
    }
}
#endif
