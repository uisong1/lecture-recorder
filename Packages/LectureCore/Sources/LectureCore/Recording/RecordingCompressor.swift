#if canImport(SwiftData)
import Foundation
import SwiftData

/// 정지한 녹음(CAF)을 m4a로 압축해 `Recording`의 경로를 바꾼다.
///
/// 압축하는 동안에도 `Recording`은 CAF를 가리키고 있어 재생할 수 있다. 압축이 끝나 m4a가 자리 잡은 뒤에야
/// 경로를 바꾸고 CAF를 지우므로, 어느 시점에 앱이 꺼져도 녹음이 사라지지 않는다.
/// 실패하거나 꺼진 압축은 다음 실행 때 `compressPending()`이 이어서 한다.
/// 같은 녹음을 두 곳에서 동시에 압축하지 않도록 압축 중인 녹음을 기억한다.
@MainActor
final class CompressionTracker {
    private var active: Set<PersistentIdentifier> = []

    /// 압축을 시작해도 되면 표시하고 true를 돌려준다. 이미 압축 중이면 false.
    func begin(_ id: PersistentIdentifier) -> Bool {
        active.insert(id).inserted
    }

    func end(_ id: PersistentIdentifier) {
        active.remove(id)
    }
}

@MainActor
public struct RecordingCompressor {
    private let context: ModelContext
    private let storage: RecordingStorage
    private let files: any FileStoring
    private let converter: any AudioConverting
    /// 지금 압축 중인 녹음. 이 압축기를 복사해 쓰는 곳(앱 시작 압축, 정지 직후 압축)이 함께 본다.
    private let tracker = CompressionTracker()

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

    /// 이미 있는 압축본이 원본 CAF 길이를 다 담았으면 그 길이(초)를, 아니거나 잴 수 없으면 nil을 돌려준다.
    private func verifiedDuration(of compressed: URL, matching source: URL) async -> TimeInterval? {
        do {
            let sourceSeconds = try await converter.duration(of: source)
            let compressedSeconds = try await converter.duration(of: compressed)
            guard ConversionCheck.isComplete(sourceSeconds: sourceSeconds, convertedSeconds: compressedSeconds) else {
                Log.recording.error("이미 있는 압축본이 짧아 다시 압축: 원본 \(sourceSeconds, privacy: .public)초, 압축본 \(compressedSeconds, privacy: .public)초")
                return nil
            }
            return sourceSeconds
        } catch {
            Log.recording.error("이미 있는 압축본 길이를 재지 못해 다시 압축: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// 기록이 지워졌는지. 지워진 모델의 속성을 읽거나 고치면 안 된다.
    private static func isGone(_ recording: Recording) -> Bool {
        recording.isDeleted || recording.modelContext == nil
    }

    /// 녹음 하나를 압축한다. 실패하면 CAF를 그대로 두고 false를 돌려준다.
    /// 같은 녹음을 이미 다른 곳(앱 시작 때의 `compressPending()`, 정지 직후 압축)에서 압축하고 있으면 건드리지 않고 false를 돌려준다.
    @discardableResult
    public func compress(_ recording: Recording) async -> Bool {
        // 압축을 기다리는 사이 사용자가 녹음을 지웠으면 삭제된 기록을 건드리지 않는다.
        guard !Self.isGone(recording) else { return false }
        guard RecordingStorage.isWorkingPath(recording.relativePath) else { return true }
        let id = recording.persistentModelID
        guard tracker.begin(id) else {
            Log.recording.info("이미 압축 중인 녹음이라 건너뜀: \(recording.relativePath, privacy: .public)")
            return false
        }
        defer { tracker.end(id) }
        return await compressExclusively(recording)
    }

    private func compressExclusively(_ recording: Recording) async -> Bool {
        var workingPath = recording.relativePath
        var source = storage.url(for: workingPath)
        var finalPath = RecordingStorage.compressedPath(for: workingPath)
        var destination = storage.url(for: finalPath)

        guard files.fileExists(at: source) else {
            Log.recording.error("압축할 파일 없음: \(workingPath, privacy: .public)")
            return false
        }

        var duration = recording.duration
        // 지난번 압축이 m4a를 자리 잡은 뒤 저장 전에 꺼졌으면 그 m4a를 쓴다. 다만 끝까지 쓰인 것이 확인될 때만이다.
        // 중간에 끊긴 m4a를 믿고 CAF를 지우면 좋은 원본이 사라진다.
        if files.fileExists(at: destination), let verified = await verifiedDuration(of: destination, matching: source) {
            if Self.isGone(recording) { return false }
            guard recording.relativePath == workingPath else {
                // 확인하는 사이 과목을 옮겼다. CAF는 그대로 두고 다음 실행 때 새 위치에서 다시 한다.
                Log.recording.notice("압축본 확인 중 녹음이 옮겨져 다음에 다시 압축: \(workingPath, privacy: .public)")
                return false
            }
            duration = verified
        } else {
            let originalTemporary = storage.url(for: RecordingStorage.temporaryCompressedPath(for: workingPath))
            var temporaryCandidates = [originalTemporary]
            func removeTemporaries() {
                for url in temporaryCandidates where files.fileExists(at: url) {
                    do { try files.removeItem(at: url) } catch {
                        Log.recording.error("압축 임시 파일 삭제 실패 \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
            do {
                if files.fileExists(at: originalTemporary) { try files.removeItem(at: originalTemporary) }
                duration = try await converter.compress(from: source, to: originalTemporary)
                // 변환하는 동안 사용자가 녹음을 지웠으면 결과 파일을 남기지 않는다 (기록 없는 m4a가 쌓이지 않게).
                if Self.isGone(recording) {
                    removeTemporaries()
                    return false
                }
                // 압축하는 동안 사용자가 녹음을 다른 과목으로 옮겼으면 CAF가 새 폴더에 있다. 거기에 m4a를 놓는다.
                // 과목 이름을 바꿔 폴더째 옮겨졌으면 임시 파일도 새 폴더로 따라갔으니 새 위치에서 찾는다.
                if recording.relativePath != workingPath {
                    workingPath = recording.relativePath
                    temporaryCandidates.append(storage.url(for: RecordingStorage.temporaryCompressedPath(for: workingPath)))
                    guard RecordingStorage.isWorkingPath(workingPath) else {
                        removeTemporaries()
                        return false
                    }
                    source = storage.url(for: workingPath)
                    finalPath = RecordingStorage.compressedPath(for: workingPath)
                    destination = storage.url(for: finalPath)
                }
                guard let temporary = temporaryCandidates.first(where: { files.fileExists(at: $0) }) else {
                    throw CocoaError(.fileNoSuchFile)
                }
                // 길이가 맞지 않아 믿지 못한 옛 m4a는 새 압축본이 준비된 뒤에야 바꾼다.
                if files.fileExists(at: destination) { try files.removeItem(at: destination) }
                try files.moveItem(at: temporary, to: destination)
            } catch {
                Log.recording.error("압축 실패, CAF를 그대로 둠 \(workingPath, privacy: .public): \(error.localizedDescription, privacy: .public)")
                removeTemporaries()
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
