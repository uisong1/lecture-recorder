import Foundation
import Observation

/// 녹음 파일 저장 상태: 압축하지 못한 녹음, 폴더로 옮기지 못한 녹음, 되살리지 못한 녹음.
/// 로그에만 남던 실패를 설정 > 녹음 파일과 모든 녹음 화면 위에 보인다 (TODO 6-4, 시안 safety-alerts 3·4번).
@MainActor
@Observable
public final class StorageHealth {
    public enum Kind: Hashable, Sendable {
        case uncompressed, unmigrated, unrecovered
        /// 압축 안 된 녹음을 세지 못했다. "모두 잘 저장돼 있어요"라고 잘못 보이지 않게 따로 알린다.
        case checkFailed
    }

    /// 압축 안 된 녹음 수와 차지하는 크기. 크기를 못 읽은 파일은 `unknownSizes`로 센다.
    public struct UncompressedSummary: Equatable, Sendable {
        public let count: Int
        public let bytes: Int64
        public let unknownSizes: Int
        public init(count: Int, bytes: Int64, unknownSizes: Int = 0) {
            self.count = count
            self.bytes = bytes
            self.unknownSizes = unknownSizes
        }
    }

    public struct Line: Equatable, Sendable {
        public let kind: Kind
        public let title: String
        public let detail: String
    }

    public private(set) var uncompressedCount = 0
    public private(set) var uncompressedBytes: Int64 = 0
    public private(set) var unmigratedCount = 0
    public private(set) var uncompressedUnknownSizes = 0
    /// 압축 안 된 녹음을 세지 못했는지 (DB 조회 실패).
    public private(set) var uncompressedCheckFailed = false
    public private(set) var unrecoveredCount = 0
    /// 되살리지 못한 첫 번째 이유.
    public private(set) var unrecoveredReason: String?
    /// "다시 시도"를 눌렀는데도 남은 줄에 붙이는 한 줄.
    public private(set) var retryNotes: [Kind: String] = [:]
    /// 다시 시도하는 중인지. 버튼을 잠시 막는다.
    public private(set) var isRetrying = false

    /// 압축 안 된 녹음을 다시 압축한다. 앱이 정한다.
    public var retryCompression: (@MainActor () async -> Void)?
    /// 폴더 정리를 다시 시도하고 실패 개수를 돌려준다. 앱이 정한다.
    public var retryMigration: (@MainActor () async -> Int)?
    /// 압축 안 된 녹음 수를 다시 센다. 세지 못하면 nil. 앱이 정한다.
    public var countUncompressed: (@MainActor () -> UncompressedSummary?)?
    /// 꺼진 녹음 되살리기를 다시 시도하고 실패 개수와 첫 이유를 돌려준다. 앱이 정한다.
    public var retryRecovery: (@MainActor () -> (failed: Int, reason: String?))?

    public static let allGoodText = "모두 잘 저장돼 있어요"
    public static let stillFailingNote = "다시 해 봤지만 아직 안 돼요. 로그: Console 앱에서 LectureRecorder"

    public init() {}

    public var hasProblems: Bool { !lines.isEmpty }

    public var lines: [Line] {
        Self.lines(
            uncompressed: uncompressedCount,
            uncompressedBytes: uncompressedBytes,
            unmigrated: unmigratedCount,
            unrecovered: unrecoveredCount,
            uncompressedUnknownSizes: uncompressedUnknownSizes,
            uncompressedCheckFailed: uncompressedCheckFailed,
            unrecoveredReason: unrecoveredReason,
            retryNotes: retryNotes
        )
    }

    /// 모든 녹음 화면 위에 보일 한 줄. 압축 실패만 보인다(용량을 계속 차지하므로). 없으면 nil.
    public var libraryLine: Line? {
        lines.first { $0.kind == .uncompressed }
    }

    nonisolated public static func lines(
        uncompressed: Int,
        uncompressedBytes: Int64,
        unmigrated: Int,
        unrecovered: Int,
        uncompressedUnknownSizes: Int = 0,
        uncompressedCheckFailed: Bool = false,
        unrecoveredReason: String? = nil,
        retryNotes: [Kind: String] = [:]
    ) -> [Line] {
        var result: [Line] = []
        func detail(_ base: String, _ kind: Kind) -> String {
            retryNotes[kind].map { "\(base)\n\($0)" } ?? base
        }
        if uncompressedCheckFailed {
            result.append(Line(kind: .checkFailed, title: "압축 상태를 확인하지 못했어요", detail: "녹음 목록을 읽지 못했어요. 앱을 다시 켜 보세요"))
        }
        if uncompressed > 0 {
            var base = "원본(CAF)은 그대로 있어요"
            if uncompressedBytes > 0 {
                base += " · 약 \(ByteCountFormatter.string(fromByteCount: uncompressedBytes, countStyle: .file)) 차지"
            }
            if uncompressedUnknownSizes > 0 {
                base += " · \(uncompressedUnknownSizes)개는 크기를 읽지 못했어요"
            }
            result.append(Line(kind: .uncompressed, title: "압축하지 못한 녹음 \(uncompressed)개", detail: detail(base, .uncompressed)))
        }
        if unmigrated > 0 {
            result.append(Line(kind: .unmigrated, title: "폴더로 옮기지 못한 녹음 \(unmigrated)개", detail: detail("예전 폴더에 그대로 있어 재생은 돼요", .unmigrated)))
        }
        if unrecovered > 0 {
            var base = "앱이 꺼졌을 때 남은 파일을 목록에 넣지 못했어요"
            if let unrecoveredReason, !unrecoveredReason.isEmpty { base += " · \(unrecoveredReason)" }
            result.append(Line(kind: .unrecovered, title: "되살리지 못한 녹음 \(unrecovered)개", detail: detail(base, .unrecovered)))
        }
        return result
    }

    public func refreshUncompressed() {
        guard let countUncompressed else {
            Self.log("저장 상태: 압축 안 된 녹음을 셀 방법이 연결되지 않음")
            return
        }
        guard let summary = countUncompressed() else {
            uncompressedCheckFailed = true
            return
        }
        uncompressedCheckFailed = false
        uncompressedCount = summary.count
        uncompressedBytes = summary.bytes
        uncompressedUnknownSizes = summary.unknownSizes
        if summary.count == 0 { retryNotes[.uncompressed] = nil }
    }

    public func setUnmigrated(_ count: Int) {
        unmigratedCount = count
        if count == 0 { retryNotes[.unmigrated] = nil }
    }

    public func setUnrecovered(_ count: Int, reason: String? = nil) {
        unrecoveredCount = count
        unrecoveredReason = count > 0 ? reason : nil
        if count == 0 { retryNotes[.unrecovered] = nil }
    }

    /// 압축을 다시 시도한다. 끝나면 남은 개수를 다시 세고, 그래도 남으면 그 줄에 알린다.
    public func retryCompressionNow() async {
        guard !isRetrying else { return }
        guard let retryCompression else {
            Self.log("저장 상태: 압축 다시 시도가 연결되지 않음")
            retryNotes[.uncompressed] = Self.stillFailingNote
            return
        }
        isRetrying = true
        await retryCompression()
        refreshUncompressed()
        if uncompressedCount > 0 { retryNotes[.uncompressed] = Self.stillFailingNote }
        isRetrying = false
    }

    /// 폴더 정리를 다시 시도한다. 그래도 남으면 그 줄에 알린다.
    public func retryMigrationNow() async {
        guard !isRetrying else { return }
        guard let retryMigration else {
            Self.log("저장 상태: 폴더 정리 다시 시도가 연결되지 않음")
            retryNotes[.unmigrated] = Self.stillFailingNote
            return
        }
        isRetrying = true
        setUnmigrated(await retryMigration())
        if unmigratedCount > 0 { retryNotes[.unmigrated] = Self.stillFailingNote }
        isRetrying = false
    }

    /// 꺼진 녹음 되살리기를 다시 시도한다. 그래도 남으면 그 줄에 알린다.
    public func retryRecoveryNow() {
        guard !isRetrying else { return }
        guard let retryRecovery else {
            Self.log("저장 상태: 되살리기 다시 시도가 연결되지 않음")
            retryNotes[.unrecovered] = Self.stillFailingNote
            return
        }
        let result = retryRecovery()
        setUnrecovered(result.failed, reason: result.reason)
        if result.failed > 0 { retryNotes[.unrecovered] = Self.stillFailingNote }
    }

    private static func log(_ message: String) {
        #if canImport(os)
        Log.recording.error("\(message, privacy: .public)")
        #endif
    }
}
