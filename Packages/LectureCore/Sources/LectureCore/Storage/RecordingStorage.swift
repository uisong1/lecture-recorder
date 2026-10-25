import Foundation

/// 녹음 파일의 위치 규칙: `Recordings/<과목>/2026-03-02_1000.m4a`.
/// DB에는 `Recordings/` 기준 상대 경로를 저장한다.
public struct RecordingStorage: Sendable {
    public static let unclassifiedFolder = "미분류"
    public static let fileExtension = "m4a"

    /// `Recordings` 폴더.
    public let root: URL
    private let files: any FileStoring

    public init(root: URL, files: any FileStoring = LocalFileStore()) {
        self.root = root
        self.files = files
    }

    /// 앱 기본 위치: `~/Library/Application Support/LectureRecorder/Recordings` (샌드박스에서는 컨테이너 안).
    public static func defaultRoot() throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return support.appending(path: LectureCore.appName, directoryHint: .isDirectory)
            .appending(path: "Recordings", directoryHint: .isDirectory)
    }

    /// 과목 이름을 폴더 이름으로 쓸 수 있게 바꾼다. nil이나 빈 이름은 미분류.
    public static func folderName(for subjectName: String?) -> String {
        let trimmed = (subjectName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return unclassifiedFolder }
        let cleaned = trimmed
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        // 숨김 파일이나 상위 폴더로 해석되지 않게 앞의 점을 없앤다.
        let withoutLeadingDots = String(cleaned.drop(while: { $0 == "." }))
        return withoutLeadingDots.isEmpty ? unclassifiedFolder : withoutLeadingDots
    }

    /// "2026-03-02_1000" 형식의 기본 파일 이름 (확장자 제외).
    public static func baseFileName(for startedAt: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: startedAt)
        func pad(_ value: Int?) -> String {
            let v = value ?? 0
            return v < 10 ? "0\(v)" : "\(v)"
        }
        return "\(c.year ?? 0)-\(pad(c.month))-\(pad(c.day))_\(pad(c.hour))\(pad(c.minute))"
    }

    /// 새 녹음의 상대 경로. 같은 이름이 있으면 `_2`, `_3` …을 붙인다.
    public func newRelativePath(subjectName: String?, startedAt: Date, calendar: Calendar) -> String {
        let folder = Self.folderName(for: subjectName)
        let base = Self.baseFileName(for: startedAt, calendar: calendar)
        return availableRelativePath(folder: folder, baseName: base)
    }

    /// `folder` 안에서 `baseName`으로 쓸 수 있는 상대 경로.
    public func availableRelativePath(folder: String, baseName: String) -> String {
        var candidate = "\(folder)/\(baseName).\(Self.fileExtension)"
        var suffix = 2
        while files.fileExists(at: url(for: candidate)) {
            candidate = "\(folder)/\(baseName)_\(suffix).\(Self.fileExtension)"
            suffix += 1
        }
        return candidate
    }

    /// 상대 경로의 실제 위치.
    public func url(for relativePath: String) -> URL {
        root.appending(path: relativePath, directoryHint: .notDirectory)
    }

    /// 파일을 쓰기 전에 과목 폴더를 만든다.
    public func prepareFolder(for relativePath: String) throws {
        try files.createDirectory(at: url(for: relativePath).deletingLastPathComponent())
    }
}
