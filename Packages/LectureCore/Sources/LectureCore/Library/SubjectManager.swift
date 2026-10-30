#if canImport(SwiftData)
import Foundation
import Observation
import SwiftData

public enum SubjectError: Error, Equatable, LocalizedError {
    case emptyName
    case duplicateName(String)
    case reservedName(String)
    case folderExists(String)
    case recordingInProgress
    case moveFailed(String)
    case saveFailed(String)

    public var errorDescription: String? {
        switch self {
        case .emptyName: "과목 이름을 입력하세요."
        case .duplicateName(let name): "‘\(name)’ 과목이 이미 있습니다."
        case .reservedName(let name): "‘\(name)’은(는) 과목 이름으로 쓸 수 없습니다."
        case .folderExists(let name): "‘\(name)’ 폴더가 이미 있어 이름을 바꾸지 않았습니다. 폴더를 먼저 정리하세요."
        case .recordingInProgress: "녹음 중이거나 압축 중인 녹음이 있어 지금은 이름을 바꿀 수 없습니다. 끝난 뒤에 바꾸세요."
        case .moveFailed(let reason): "녹음 폴더를 옮기지 못해 이름을 바꾸지 않았습니다: \(reason)"
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
    private let storage: RecordingStorage?
    /// 지금 녹음 중인 파일의 상대 경로. 그 파일이 든 과목은 이름을 바꾸지 않는다.
    public var activePaths: @MainActor () -> Set<String> = { [] }

    /// - Parameter storage: 주면 과목 이름을 바꿀 때 녹음 폴더와 녹음 경로도 함께 옮긴다.
    public init(context: ModelContext, storage: RecordingStorage? = nil) {
        self.context = context
        self.storage = storage
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
        guard let storage else {
            subject.name = name
            try save()
            return
        }
        try renameMovingFolder(subject, to: name, storage: storage)
    }

    /// 이름과 함께 `Recordings/<학기>/<옛 이름>/`을 새 이름 폴더로 옮기고 녹음 경로를 고친다.
    /// 폴더 이동이나 저장이 실패하면 이름·경로·폴더가 모두 이전 상태로 남는다.
    private func renameMovingFolder(_ subject: Subject, to name: String, storage: RecordingStorage) throws(SubjectError) {
        let oldName = subject.name
        let oldFolder = RecordingStorage.folderPath(semester: subject.semester, subjectName: oldName)
        let newFolder = RecordingStorage.folderPath(semester: subject.semester, subjectName: name)
        let oldPrefix = oldFolder + "/"
        let inFolder = subject.recordings.filter { $0.relativePath.hasPrefix(oldPrefix) }

        // 녹음 중인 파일은 정지하기 전에는 DB에 없으므로 `inFolder`로는 알 수 없다. 경로로 직접 확인한다.
        // 폴더를 옮기면 녹음기는 옮겨진 파일에 계속 쓰지만 저장될 기록은 옛 경로를 가리켜 녹음이 사라진 것처럼 된다.
        let active = activePaths()
        guard !active.contains(where: { $0.hasPrefix(oldPrefix) }),
              !inFolder.contains(where: { RecordingStorage.isWorkingPath($0.relativePath) || active.contains($0.relativePath) })
        else {
            throw .recordingInProgress
        }
        guard oldFolder != newFolder else {
            subject.name = name
            try save()
            return
        }
        let isCaseOnly = oldFolder.compare(newFolder, options: .caseInsensitive) == .orderedSame
        if !isCaseOnly, storage.folderExists(newFolder) { throw .folderExists(name) }

        let oldPaths = inFolder.map { ($0, $0.relativePath) }
        // 영상도 보관한 녹음은 영상 파일도 같은 폴더에 있어 함께 따라간다.
        let oldVideoPaths = inFolder.compactMap { recording in recording.videoRelativePath.map { (recording, $0) } }
        func apply(name: String, folder: String) {
            subject.name = name
            for (recording, path) in oldPaths { recording.relativePath = folder + "/" + path.dropFirst(oldPrefix.count) }
            for (recording, path) in oldVideoPaths where path.hasPrefix(oldPrefix) {
                recording.videoRelativePath = folder + "/" + path.dropFirst(oldPrefix.count)
            }
        }

        let moved = storage.folderExists(oldFolder)
        if moved {
            do {
                try storage.moveFolder(from: oldFolder, to: newFolder, protecting: active)
            } catch {
                Log.storage.error("과목 폴더 이동 실패 \(oldFolder, privacy: .public): \(error.localizedDescription, privacy: .public)")
                throw .moveFailed(error.localizedDescription)
            }
        }
        apply(name: name, folder: newFolder)
        do {
            try context.save()
        } catch {
            Log.data.error("과목 이름 저장 실패: \(error.localizedDescription, privacy: .public)")
            context.rollback()
            apply(name: oldName, folder: oldFolder)
            if moved {
                do {
                    try storage.moveFolder(from: newFolder, to: oldFolder)
                } catch {
                    // 폴더를 되돌리지 못했으면 기록이 파일을 따라가게 한다. 녹음이 사라지는 것보다 새 이름으로 남는 편이 낫다.
                    Log.storage.error("과목 폴더를 되돌리지 못함 \(newFolder, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    apply(name: name, folder: newFolder)
                    try? context.save()
                }
            }
            reload()
            throw .saveFailed(error.localizedDescription)
        }
        reload()
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
