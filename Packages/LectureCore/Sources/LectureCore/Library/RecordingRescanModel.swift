#if canImport(SwiftData)
import Foundation
import Observation

/// 설정의 "녹음 폴더 다시 읽기" 버튼 상태.
@MainActor
@Observable
public final class RecordingRescanModel {
    public private(set) var isRunning = false
    public private(set) var message: String?
    /// `message`가 실패 안내이면 true.
    public private(set) var isError = false

    private let rescanner: RecordingRescanner
    private let activePaths: @MainActor () -> Set<String>
    private let onFinished: @MainActor () -> Void

    /// - Parameters:
    ///   - activePaths: 지금 녹음 중이라 건드리면 안 되는 파일의 상대 경로.
    ///   - onFinished: 끝난 뒤 목록을 다시 불러오는 일.
    public init(rescanner: RecordingRescanner, activePaths: @escaping @MainActor () -> Set<String> = { [] }, onFinished: @escaping @MainActor () -> Void = {}) {
        self.rescanner = rescanner
        self.activePaths = activePaths
        self.onFinished = onFinished
    }

    public func run() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        do {
            let report = try await rescanner.rescan(skipping: activePaths())
            message = report.summary
            isError = false
        } catch {
            Log.storage.error("녹음 폴더 다시 읽기 실패: \(error.localizedDescription, privacy: .public)")
            message = error.localizedDescription
            isError = true
        }
        onFinished()
    }
}
#endif
