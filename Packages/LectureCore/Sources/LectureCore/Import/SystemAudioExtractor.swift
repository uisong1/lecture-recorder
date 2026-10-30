#if canImport(AVFoundation)
import AVFoundation

/// `AVAssetExportSession`으로 영상에서 소리 트랙만 m4a로 꺼낸다.
/// 가능하면 다시 인코딩하지 않고 그대로 옮겨(passthrough) 음질을 낮추지 않는다. 그게 안 되는 소리 형식일 때만 AAC로 다시 쓴다.
public struct SystemAudioExtractor: AudioExtracting {
    public init() {}

    public func extractAudio(from source: URL, to destination: URL) async throws -> TimeInterval {
        let name = source.lastPathComponent
        let asset = AVURLAsset(url: source)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else { throw MediaImportError.noAudio(name) }
        let sourceDuration = try await asset.load(.duration)
        guard sourceDuration.isNumeric, sourceDuration.seconds > 0 else { throw MediaImportError.unplayable(name) }

        // 영상 트랙이 섞여 있으면 m4a로 내보낼 수 없어서 소리 트랙만 담은 조합을 만든다.
        let composition = AVMutableComposition()
        guard let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw MediaImportError.fileFailed("소리 트랙을 만들지 못했습니다")
        }
        try audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: sourceDuration), of: track, at: .zero)

        var lastError: Error = MediaImportError.fileFailed("내보내기를 시작하지 못했습니다")
        for preset in [AVAssetExportPresetPassthrough, AVAssetExportPresetAppleM4A] {
            try? FileManager.default.removeItem(at: destination)
            guard let session = AVAssetExportSession(asset: composition, presetName: preset) else { continue }
            session.outputURL = destination
            session.outputFileType = .m4a
            nonisolated(unsafe) let exporting = session
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                exporting.exportAsynchronously { continuation.resume() }
            }
            guard session.status == .completed else {
                lastError = session.error ?? lastError
                Log.storage.notice("소리 추출 실패(\(preset, privacy: .public)): \(lastError.localizedDescription, privacy: .public)")
                continue
            }
            // 쓴 파일이 원본 길이를 담았는지 다시 열어서 확인한다.
            let written = try await AVURLAsset(url: destination).load(.duration)
            guard written.isNumeric, ConversionCheck.isComplete(sourceSeconds: sourceDuration.seconds, convertedSeconds: written.seconds) else {
                lastError = MediaImportError.unplayable(name)
                continue
            }
            return written.seconds
        }
        try? FileManager.default.removeItem(at: destination)
        throw lastError
    }
}
#endif
