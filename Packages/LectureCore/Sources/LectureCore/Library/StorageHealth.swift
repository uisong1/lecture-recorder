import Foundation
import Observation

/// 녹음 파일 저장 상태: 압축하지 못한 녹음, 폴더로 옮기지 못한 녹음, 되살리지 못한 녹음.
/// 로그에만 남던 실패를 설정 > 녹음 파일과 모든 녹음 화면 위에 보인다 (TODO 6-4, 시안 safety-alerts 3·4번).
@MainActor
@Observable
public final class StorageHealth {
    public enum Kind: Hashable, Sendable {
        case uncompressed, unmigrated, unrecovered
    }

    public struct Line: Equatable, Sendable {
        public let kind: Kind
        public let title: String
        public let detail: String
    }

    public private(set) var uncompressedCount = 0
    public private(set) var uncompressedBytes: Int64 = 0
    public private(set) var unmigratedCount = 0
    public private(set) var unrecoveredCount = 0
    /// 다시 시도하는 중인지. 버튼을 잠시 막는다.
    public private(set) var isRetrying = false

    /// 압축 안 된 녹음을 다시 압축한다. 앱이 정한다.
    public var retryCompression: (@MainActor () async -> Void)?
    /// 폴더 정리를 다시 시도하고 실패 개수를 돌려준다. 앱이 정한다.
    public var retryMigration: (@MainActor () async -> Int)?
    /// 압축 안 된 녹음 수를 다시 센다. 앱이 정한다.
    public var countUncompressed: (@MainActor () -> (count: Int, bytes: Int64))?

    public static let allGoodText = "모두 잘 저장돼 있어요"

    public init() {}

    public var hasProblems: Bool { !lines.isEmpty }

    public var lines: [Line] {
        Self.lines(uncompressed: uncompressedCount, uncompressedBytes: uncompressedBytes, unmigrated: unmigratedCount, unrecovered: unrecoveredCount)
    }

    /// 모든 녹음 화면 위에 보일 한 줄. 압축 실패만 보인다(용량을 계속 차지하므로). 없으면 nil.
    public var libraryLine: Line? {
        lines.first { $0.kind == .uncompressed }
    }

    nonisolated public static func lines(uncompressed: Int, uncompressedBytes: Int64, unmigrated: Int, unrecovered: Int) -> [Line] {
        var result: [Line] = []
        if uncompressed > 0 {
            let size = ByteCountFormatter.string(fromByteCount: uncompressedBytes, countStyle: .file)
            let detail = uncompressedBytes > 0 ? "원본(CAF)은 그대로 있어요 · 약 \(size) 차지" : "원본(CAF)은 그대로 있어요"
            result.append(Line(kind: .uncompressed, title: "압축하지 못한 녹음 \(uncompressed)개", detail: detail))
        }
        if unmigrated > 0 {
            result.append(Line(kind: .unmigrated, title: "폴더로 옮기지 못한 녹음 \(unmigrated)개", detail: "예전 폴더에 그대로 있어 재생은 돼요"))
        }
        if unrecovered > 0 {
            result.append(Line(kind: .unrecovered, title: "되살리지 못한 녹음 \(unrecovered)개", detail: "앱이 꺼졌을 때 남은 파일을 목록에 넣지 못했어요"))
        }
        return result
    }

    public func refreshUncompressed() {
        guard let countUncompressed else { return }
        let summary = countUncompressed()
        uncompressedCount = summary.count
        uncompressedBytes = summary.bytes
    }

    public func setUnmigrated(_ count: Int) { unmigratedCount = count }
    public func setUnrecovered(_ count: Int) { unrecoveredCount = count }

    /// 압축을 다시 시도한다. 끝나면 남은 개수를 다시 센다.
    public func retryCompressionNow() async {
        guard !isRetrying, let retryCompression else { return }
        isRetrying = true
        await retryCompression()
        refreshUncompressed()
        isRetrying = false
    }

    /// 폴더 정리를 다시 시도한다.
    public func retryMigrationNow() async {
        guard !isRetrying, let retryMigration else { return }
        isRetrying = true
        unmigratedCount = await retryMigration()
        isRetrying = false
    }
}
