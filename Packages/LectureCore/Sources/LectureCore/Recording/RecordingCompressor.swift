#if canImport(SwiftData)
import Foundation
import SwiftData

/// 정지한 녹음(CAF)을 m4a로 압축해 `Recording`의 경로를 바꾼다.
///
/// 압축하는 동안에도 `Recording`은 CAF를 가리키고 있어 재생할 수 있다. 압축이 끝나 m4a가 자리 잡은 뒤에야
/// 경로를 바꾸고 CAF를 지우므로, 어느 시점에 앱이 꺼져도 녹음이 사라지지 않는다.
/// 실패하거나 꺼진 압축은 다음 실행 때 `compressPending()`이 이어서 한다.
@MainActor
public struct RecordingCompressor {
    private let context: ModelContext
    private let storage: RecordingStorage
    private let files: any FileStoring
    private let converter: any AudioConverting

    public init(
        context: ModelContext,
        storage: RecordingStorage,
        files: any FileStoring = LocalFileStore(),
        converter: any AudioConverting
    ) {
        self.context = context
        self.storage = storage
        self.files = files
        self.converter = converter
    }

    /// 아직 CAF인 녹음을 모두 압축한다. 성공한 개수를 돌려준다.
    @discardableResult
    public func compressPending() async -> Int {
        let pending: [Recording]
        do {
            pending = try context.fetch(FetchDescriptor<Recording>()).filter { RecordingStorage.isWorkingPath($0.relativePath) }
        } catch {
            Log.recording.error("압축할 녹음 조회 실패: \(error.localizedDescription, privacy: .public)")
            return 0
        }
        var done = 0
        for recording in pending where await compress(recording) {
            done += 1
        }
        return done
    }

    /// 녹음 하나를 압축한다. 실패하면 CAF를 그대로 두고 false를 돌려준다.
    @discardableResult
    public func compress(_ recording: Recording) async -> Bool {
        let workingPath = recording.relativePath
        guard RecordingStorage.isWorkingPath(workingPath) else { return true }
        let source = storage.url(for: workingPath)
        let finalPath = RecordingStorage.compressedPath(for: workingPath)
        let destination = storage.url(for: finalPath)
        let temporary = storage.url(for: RecordingStorage.temporaryCompressedPath(for: workingPath))

        guard files.fileExists(at: source) else {
            Log.recording.error("압축할 파일 없음: \(workingPath, privacy: .public)")
            return false
        }

        var duration = recording.duration
        if !files.fileExists(at: destination) {
            do {
                if files.fileExists(at: temporary) { try files.removeItem(at: temporary) }
                duration = try await converter.compress(from: source, to: temporary)
                try files.moveItem(at: temporary, to: destination)
            } catch {
                Log.recording.error("압축 실패, CAF를 그대로 둠 \(workingPath, privacy: .public): \(error.localizedDescription, privacy: .public)")
                try? files.removeItem(at: temporary)
                return false
            }
        }

        let previousDuration = recording.duration
        recording.relativePath = finalPath
        recording.duration = duration
        do {
            try context.save()
        } catch {
            // 경로를 되돌려 CAF를 가리키게 두고, 다음 실행 때 다시 시도한다.
            recording.relativePath = workingPath
            recording.duration = previousDuration
            Log.recording.error("압축 결과 저장 실패 \(workingPath, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
        do {
            try files.removeItem(at: source)
        } catch {
            Log.recording.error("CAF 삭제 실패 \(workingPath, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        Log.recording.info("압축 완료: \(finalPath, privacy: .public)")
        return true
    }
}
#endif
