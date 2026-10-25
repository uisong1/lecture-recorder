#if canImport(SwiftData)
import Foundation
import Observation
import SwiftData

/// "녹음 폴더 다시 읽기" 결과.
public struct RescanReport: Equatable, Sendable {
    /// 목록에 되살린 녹음 수.
    public var restored = 0
    /// 되살린 것 중 파일을 열 수 없어 길이를 크기로 어림한 수.
    public var estimatedLength = 0
    /// 비어 있거나 읽을 수 없어 되살리지 못한 파일 수.
    public var unreadable = 0
    /// 정리한 빈 폴더 수.
    public var removedEmptyFolders = 0

    public init(restored: Int = 0, estimatedLength: Int = 0, unreadable: Int = 0, removedEmptyFolders: Int = 0) {
        self.restored = restored
        self.estimatedLength = estimatedLength
        self.unreadable = unreadable
        self.removedEmptyFolders = removedEmptyFolders
    }

    /// 화면에 보일 한 줄 요약.
    public var summary: String {
        var parts: [String]
        if restored == 0 && unreadable == 0 {
            parts = ["목록에 없는 녹음 파일이 없습니다."]
        } else {
            parts = ["\(restored)개를 목록에 되살렸습니다."]
            if estimatedLength > 0 { parts.append("그중 \(estimatedLength)개는 길이를 읽지 못해 파일 크기로 어림했습니다.") }
            if unreadable > 0 { parts.append("\(unreadable)개는 열 수 없어 건너뛰었습니다.") }
        }
        if removedEmptyFolders > 0 { parts.append("빈 폴더 \(removedEmptyFolders)개를 정리했습니다.") }
        return parts.joined(separator: " ")
    }
}

public enum RescanError: Error, Equatable, LocalizedError {
    case databaseFailed(String)

    public var errorDescription: String? {
        switch self {
        case .databaseFailed(let reason): "녹음 목록을 읽거나 저장하지 못했습니다: \(reason)"
        }
    }
}

/// `Recordings/` 아래에 있는데 목록(DB)에 없는 오디오 파일을 `Recording`으로 되살린다.
/// 앱을 새로 설치했거나 저장소를 잃었을 때, 휴지통에서 되돌린 파일을 다시 목록에 넣을 때 쓴다.
///
/// 파일은 옮기거나 지우지 않는다. 이미 있는 기록과 북마크도 건드리지 않는다.
/// 파일 정리는 끝에서 **비어 있는 폴더**를 지우는 것뿐이다.
@MainActor
public struct RecordingRescanner {
    private let context: ModelContext
    private let storage: RecordingStorage
    private let durations: any AudioDurationReading
    private let calendar: Calendar

    public init(context: ModelContext, storage: RecordingStorage, durations: any AudioDurationReading, calendar: Calendar = .current) {
        self.context = context
        self.storage = storage
        self.durations = durations
        self.calendar = calendar
    }

    /// - Parameter activePaths: 지금 녹음 중이거나 압축 중이라 건드리면 안 되는 파일의 상대 경로.
    public func rescan(skipping activePaths: Set<String> = []) async throws(RescanError) -> RescanReport {
        let known: Set<String>
        let subjects: [Subject]
        do {
            known = Set(try context.fetch(FetchDescriptor<Recording>()).map(\.relativePath))
            subjects = try context.fetch(FetchDescriptor<Subject>())
        } catch {
            throw .databaseFailed(error.localizedDescription)
        }

        var report = RescanReport()
        for path in Self.pathsToRestore(storage.audioFilePaths(), known: known, active: activePaths) {
            // 파일을 하나씩 열어 보는 사이에 화면에 양보한다.
            await Task.yield()
            let url = storage.url(for: path)
            guard let size = storage.fileSize(at: path), size > 0 else {
                Log.storage.notice("비어 있거나 읽을 수 없어 되살리지 않음: \(path, privacy: .public)")
                report.unreadable += 1
                continue
            }
            let measured = await durations.duration(of: url)
            if measured == nil { report.estimatedLength += 1 }
            let duration = measured ?? Double(size) * 8 / (RecordingStorage.isWorkingPath(path) ? RecordingRecovery.workingBitsPerSecond : RecordingRecovery.bitsPerSecond)

            let subject = Self.subject(forPath: path, in: subjects)
            let (title, startedAt) = titleAndStart(forPath: path, subject: subject)
            context.insert(Recording(title: title, subject: subject, startedAt: startedAt, duration: duration, relativePath: path))
            report.restored += 1
        }

        if context.hasChanges {
            do {
                try context.save()
            } catch {
                context.rollback()
                throw .databaseFailed(error.localizedDescription)
            }
        }
        report.removedEmptyFolders = storage.removeEmptyFolders()
        if report.restored > 0 || report.unreadable > 0 {
            Log.storage.notice("녹음 폴더 다시 읽기: 되살림 \(report.restored, privacy: .public), 건너뜀 \(report.unreadable, privacy: .public)")
        }
        return report
    }

    /// 되살릴 파일 경로. 같은 이름의 압축 전(CAF)·후(m4a) 파일은 한 녹음으로 보아, 한쪽이라도 이미 목록에 있거나
    /// 녹음 중이면 건너뛰고, 둘 다 없으면 m4a를 고른다.
    static func pathsToRestore(_ paths: [String], known: Set<String>, active: Set<String>) -> [String] {
        func stem(_ path: String) -> String { (path as NSString).deletingPathExtension }
        let blockedStems = Set(known.union(active).map(stem))
        var chosen: [String: String] = [:]
        for path in paths where !blockedStems.contains(stem(path)) {
            let key = stem(path)
            // 이미 고른 쪽이 m4a(압축 후)면 그대로 둔다.
            if let existing = chosen[key], !RecordingStorage.isWorkingPath(existing) { continue }
            chosen[key] = path
        }
        return paths.filter { chosen[stem($0)] == $0 }
    }

    /// 폴더 이름으로 과목을 찾는다: `<학기>/<과목>/파일`은 과목 폴더, `<과목>/파일`은 첫 폴더가 과목이다.
    /// 같은 이름의 과목이 여럿이면 학기 폴더까지 맞는 쪽을 쓴다. 맞는 과목이 없거나 `미분류`면 nil.
    static func subject(forPath path: String, in subjects: [Subject]) -> Subject? {
        let folders = path.split(separator: "/").dropLast().map(String.init)
        guard let subjectFolder = folders.count >= 2 ? folders[1] : folders.first,
              subjectFolder != RecordingStorage.unclassifiedFolder
        else { return nil }
        let matches = subjects.filter { RecordingStorage.folderName(for: $0.name) == subjectFolder }
        guard matches.count > 1, folders.count >= 2 else { return matches.first }
        return matches.first { RecordingStorage.folderName(for: $0.semester) == folders[0] } ?? matches.first
    }

    private func titleAndStart(forPath path: String, subject: Subject?) -> (title: String, startedAt: Date) {
        let fileName = (path as NSString).lastPathComponent
        let folders = path.split(separator: "/").dropLast().map(String.init)
        let modified = storage.modificationDate(at: path)
        // 지금 규칙의 파일 이름에는 연도가 없다: 학기 폴더(또는 과목의 학기), 없으면 수정 시각의 연도를 쓴다.
        let semesterYear = folders.count >= 2 ? RecordingFileName.year(fromSemester: folders[0]) : nil
        let year = semesterYear ?? subject.flatMap { RecordingFileName.year(fromSemester: $0.semester) } ?? modified.map { calendar.component(.year, from: $0) }
        if let parsed = RecordingFileName.startedAt(fromFileName: fileName, yearHint: year, calendar: calendar) {
            let name = subject?.name ?? SubjectManager.unclassifiedName
            return (RecordingController.defaultTitle(subjectName: name, startedAt: parsed, calendar: calendar), parsed)
        }
        let base = RecordingFileName.stem(fileName)
        return (base.isEmpty ? fileName : base, modified ?? Date(timeIntervalSince1970: 0))
    }
}
#endif
