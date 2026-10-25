import Foundation

/// 앱을 켤 때 SwiftData 저장소 파일을 하루에 한 번 복사해 두고, 최근 3개와 지난 4주의 주마다 하나씩만 남긴다.
/// 저장소를 열기 **전에** 부른다: 저장소가 열리지 않거나 망가져도 직전 날짜의 사본이 남도록.
///
/// `Backups/2026-10-25/default.store` 같은 모양이다. 복사하는 동안 앱이 꺼져도 하루가 "백업됨"으로 잘못 남지 않도록
/// 부속 파일(-wal, -shm)을 먼저 복사하고 본 파일(.store)을 마지막에 복사한다 (본 파일이 있어야 그날 백업이 끝난 것으로 본다).
public struct StoreBackup: Sendable {
    public enum Outcome: Equatable, Sendable {
        /// 저장소 파일이 아직 없어서 (처음 켠 경우) 할 일이 없다.
        case noStore
        /// 오늘 백업이 이미 있어서 새로 만들지 않았다.
        case alreadyBackedUp
        /// 새로 백업했다. `removedOld`는 개수 제한으로 지운 오래된 백업 수.
        case created(day: String, removedOld: Int)
        /// 복사하지 못했다. 앱은 그대로 켠다.
        case failed(String)
    }

    /// 날짜와 상관없이 남길 가장 최근 백업 수 (날짜 폴더 기준).
    public static let keepCount = 3
    /// 주마다 하나씩 남길 주 수 (이번 주를 포함한 달력상의 주).
    public static let keepWeeks = 4
    /// 저장소 본 파일 뒤에 붙는 부속 파일 접미사.
    public static let sidecarSuffixes = ["-wal", "-shm"]

    private let storeURL: URL
    private let backupsRoot: URL
    private let files: any FileStoring
    private let now: @Sendable () -> Date
    private let calendar: Calendar

    public init(
        storeURL: URL,
        backupsRoot: URL,
        files: any FileStoring = LocalFileStore(),
        now: @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.storeURL = storeURL
        self.backupsRoot = backupsRoot
        self.files = files
        self.now = now
        self.calendar = calendar
    }

    /// 앱 기본 위치: `~/Library/Application Support/LectureRecorder/Backups`.
    public static func defaultRoot() throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return support.appending(path: LectureCore.appName, directoryHint: .isDirectory)
            .appending(path: "Backups", directoryHint: .isDirectory)
    }

    /// "2026-10-25" 형식의 날짜 폴더 이름.
    static func dayName(for date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        func pad(_ value: Int?) -> String {
            let v = value ?? 0
            return v < 10 ? "0\(v)" : "\(v)"
        }
        return "\(c.year ?? 0)-\(pad(c.month))-\(pad(c.day))"
    }

    static func isDayName(_ name: String) -> Bool {
        let parts = name.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2 else { return false }
        return parts.allSatisfy { part in part.allSatisfy { $0.isASCII && $0.isNumber } }
    }

    /// 지워도 되는 날짜 폴더 이름을 고른다. 최근 `keepCount`개와, 이번 주를 포함한 `keepWeeks`주 안의 주마다
    /// 가장 오래된 하나는 남긴다. 날짜 형식이 아니거나 없는 날짜(2026-13-45)인 이름은 지우지 않는다.
    static func daysToRemove(from names: [String], now: Date, calendar userCalendar: Calendar) -> [String] {
        // 사용자의 첫 요일 설정과 상관없이 주는 월요일에 시작한다 (같은 백업이 환경마다 다르게 남지 않도록).
        var calendar = userCalendar
        calendar.firstWeekday = 2
        let days = names.filter(isDayName)
        var dated: [(name: String, date: Date)] = []
        for name in days {
            let parts = name.split(separator: "-").compactMap { Int($0) }
            let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
            guard let date = calendar.date(from: components), dayName(for: date, calendar: calendar) == name else { continue }
            dated.append((name, date))
        }
        let recent = Set(dated.map { $0.name }.sorted(by: >).prefix(keepCount))
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now),
              let windowStart = calendar.date(byAdding: .weekOfYear, value: -(keepWeeks - 1), to: thisWeek.start) else {
            return dated.map { $0.name }.filter { !recent.contains($0) }.sorted()
        }
        var oldestOfWeek: [Date: String] = [:]
        for (name, date) in dated.sorted(by: { $0.name < $1.name }) {
            guard let week = calendar.dateInterval(of: .weekOfYear, for: date), week.start >= windowStart else { continue }
            if oldestOfWeek[week.start] == nil { oldestOfWeek[week.start] = name }
        }
        let keep = recent.union(oldestOfWeek.values)
        return dated.map { $0.name }.filter { !keep.contains($0) }.sorted()
    }

    @discardableResult
    public func backupIfNeeded() -> Outcome {
        guard files.fileExists(at: storeURL) else { return .noStore }
        let day = Self.dayName(for: now(), calendar: calendar)
        let folder = backupsRoot.appending(path: day, directoryHint: .isDirectory)
        let storeName = storeURL.lastPathComponent
        let sourceSize = files.fileSize(at: storeURL)

        // 본 파일이 있으면 그날 백업은 끝난 것이다 (하루에 한 번).
        if files.fileExists(at: folder.appending(path: storeName)) { return .alreadyBackedUp }
        // 본 파일 없이 남은 폴더는 끝나지 못한 지난 시도의 조각이라 치우고 처음부터 다시 한다.
        if files.fileExists(at: folder) { try? files.removeItem(at: folder) }

        do {
            try files.createDirectory(at: folder)
            for suffix in Self.sidecarSuffixes + [""] {
                let source = URL(filePath: storeURL.path(percentEncoded: false) + suffix)
                guard files.fileExists(at: source) else { continue }
                try files.copyItem(at: source, to: folder.appending(path: source.lastPathComponent))
            }
            guard files.fileSize(at: folder.appending(path: storeName)) == sourceSize else {
                throw CocoaError(.fileWriteUnknown)
            }
        } catch {
#if canImport(os)
            Log.storage.error("저장소 백업 실패: \(error.localizedDescription, privacy: .public)")
#endif
            // 끝나지 않은 사본이 남아 오늘 다시 시도하지 못하거나 개수 제한을 차지하지 않도록 치운다.
            try? files.removeItem(at: folder)
            return .failed(error.localizedDescription)
        }
        return .created(day: day, removedOld: pruneOldBackups())
    }

    /// 보관 규칙(`daysToRemove`)에 들지 않는 오래된 백업을 지운다. 지운 개수를 돌려준다.
    private func pruneOldBackups() -> Int {
        let entries: [URL]
        do {
            entries = try files.contentsOfDirectory(at: backupsRoot)
        } catch {
#if canImport(os)
            Log.storage.error("백업 목록을 읽지 못했습니다: \(error.localizedDescription, privacy: .public)")
#endif
            return 0
        }
        var removed = 0
        for old in Self.daysToRemove(from: entries.map(\.lastPathComponent), now: now(), calendar: calendar) {
            do {
                try files.removeItem(at: backupsRoot.appending(path: old, directoryHint: .isDirectory))
                removed += 1
            } catch {
#if canImport(os)
                Log.storage.error("오래된 백업을 지우지 못했습니다 \(old, privacy: .public): \(error.localizedDescription, privacy: .public)")
#endif
            }
        }
        return removed
    }
}
