#if canImport(SwiftData)
import Foundation
import SwiftData

/// 예전 폴더 규칙(`<과목>/2026-03-02_1000.m4a`)의 녹음을 새 규칙(`<학기>/<과목>/03-02 월 10-00.m4a`)으로 옮긴 결과.
public struct RecordingMigrationReport: Equatable, Sendable {
    /// 새 위치로 옮긴 녹음 수.
    public var moved = 0
    /// 옮기지 못하고 예전 위치에 그대로 둔 녹음 수. 재생은 계속 된다.
    public var failed = 0
    /// 파일이 없어 건드리지 않은 녹음 수.
    public var missing = 0

    public init(moved: Int = 0, failed: Int = 0, missing: Int = 0) {
        self.moved = moved
        self.failed = failed
        self.missing = missing
    }
}

/// 예전 규칙의 녹음 파일을 새 폴더 구조로 안전하게 옮긴다.
///
/// 파일을 "이동"하지 않고 먼저 복사한 뒤 크기가 같은지 확인하고, DB 경로를 바꿔 저장한 다음에야 원본을 지운다.
/// 어느 단계에서 실패해도 원본과 DB 경로는 그대로라 녹음이 사라지지 않는다. 몇 번을 실행해도 같은 결과다.
///
/// - 학기를 아는 과목과 미분류 녹음만 옮긴다. 학기를 모르는 과목의 녹음은 시간표를 가져와 학기가 정해진 뒤 옮긴다.
/// - 아직 압축되지 않은 CAF는 건드리지 않는다 (압축 흐름이 쓰는 중일 수 있다).
@MainActor
public struct RecordingMigrator {
    private let context: ModelContext
    private let storage: RecordingStorage
    private let calendar: Calendar

    public init(context: ModelContext, storage: RecordingStorage, calendar: Calendar = .current) {
        self.context = context
        self.storage = storage
        self.calendar = calendar
    }

    /// 옮길 녹음이 있으면 옮긴다. 개별 실패는 로그만 남기고 다음 녹음으로 넘어간다. 파일 하나를 옮길 때마다 화면에 양보한다.
    @discardableResult
    public func migrateIfNeeded() async -> RecordingMigrationReport {
        var report = RecordingMigrationReport()
        let recordings: [Recording]
        do {
            recordings = try context.fetch(FetchDescriptor<Recording>())
        } catch {
            Log.storage.error("녹음 폴더 정리 대상을 읽지 못했습니다: \(error.localizedDescription, privacy: .public)")
            return report
        }
        for recording in recordings where shouldMigrate(recording) {
            // 파일을 하나씩 복사하는 사이에 화면이 멈추지 않게 양보한다.
            await Task.yield()
            switch migrate(recording) {
            case .moved: report.moved += 1
            case .failed: report.failed += 1
            case .missing: report.missing += 1
            }
        }
        if report.moved > 0 || report.failed > 0 {
            Log.storage.notice("녹음 폴더 정리: 이동 \(report.moved, privacy: .public), 실패 \(report.failed, privacy: .public)")
        }
        return report
    }

    private enum Outcome { case moved, failed, missing }

    private func shouldMigrate(_ recording: Recording) -> Bool {
        let path = recording.relativePath
        guard RecordingStorage.isLegacyPath(path), !RecordingStorage.isWorkingPath(path) else { return false }
        guard let subject = recording.subject else { return true }
        return !subject.semester.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func migrate(_ recording: Recording) -> Outcome {
        let oldPath = recording.relativePath
        guard let oldSize = storage.fileSize(at: oldPath), storage.fileExists(at: storage.url(for: oldPath)) else {
            Log.storage.notice("옮길 녹음 파일 없음: \(oldPath, privacy: .public)")
            return .missing
        }
        let newPath = storage.availableRelativePath(
            folder: RecordingStorage.folderPath(semester: recording.subject?.semester, subjectName: recording.subject?.name),
            baseName: RecordingStorage.baseFileName(for: recording.startedAt, calendar: calendar),
            fileExtension: (oldPath as NSString).pathExtension
        )

        do {
            try storage.copyFile(from: oldPath, to: newPath)
        } catch {
            Log.storage.error("녹음 복사 실패 \(oldPath, privacy: .public): \(error.localizedDescription, privacy: .public)")
            discardCopy(at: newPath)
            return .failed
        }
        guard storage.fileSize(at: newPath) == oldSize else {
            Log.storage.error("복사본 크기가 다릅니다. 원본을 그대로 둡니다: \(oldPath, privacy: .public)")
            discardCopy(at: newPath)
            return .failed
        }

        recording.relativePath = newPath
        do {
            try context.save()
        } catch {
            Log.storage.error("녹음 경로 저장 실패 \(oldPath, privacy: .public): \(error.localizedDescription, privacy: .public)")
            recording.relativePath = oldPath
            discardCopy(at: newPath)
            return .failed
        }

        do {
            try storage.removeFile(at: oldPath)
        } catch {
            // 복사본이 이미 쓰이고 있으니 실패가 아니다. 원본만 남는다.
            Log.storage.error("예전 녹음 파일을 지우지 못했습니다 \(oldPath, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        return .moved
    }

    private func discardCopy(at path: String) {
        do {
            try storage.removeFile(at: path)
        } catch {
            Log.storage.error("복사본을 지우지 못했습니다 \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
#endif
