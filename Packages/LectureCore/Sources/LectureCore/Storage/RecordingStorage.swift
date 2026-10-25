import Foundation

/// 녹음 파일의 위치 규칙: `Recordings/<과목>/2026-03-02_1000.m4a`.
/// DB에는 `Recordings/` 기준 상대 경로를 저장한다.
public struct RecordingStorage: Sendable {
    public static let unclassifiedFolder = "미분류"
    /// 완성된 녹음 파일의 확장자.
    public static let fileExtension = "m4a"
    /// 녹음 중에 쓰는 확장자. 강제 종료돼도 재생할 수 있는 CAF로 쓰고, 정지 뒤에 m4a로 압축한다.
    public static let workingExtension = "caf"

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
    /// 확장자는 기본이 m4a이고, 녹음 중 파일은 `workingExtension`을 넘긴다.
    public func newRelativePath(
        subjectName: String?,
        startedAt: Date,
        calendar: Calendar,
        fileExtension: String = RecordingStorage.fileExtension
    ) -> String {
        let folder = Self.folderName(for: subjectName)
        let base = Self.baseFileName(for: startedAt, calendar: calendar)
        return availableRelativePath(folder: folder, baseName: base, fileExtension: fileExtension)
    }

    /// `folder` 안에서 `baseName`으로 쓸 수 있는 상대 경로.
    /// 압축 전 CAF와 압축된 m4a 어느 쪽이 있어도 같은 이름으로 보고 피한다.
    public func availableRelativePath(
        folder: String,
        baseName: String,
        fileExtension: String = RecordingStorage.fileExtension
    ) -> String {
        func taken(_ name: String) -> Bool {
            [Self.fileExtension, Self.workingExtension].contains { files.fileExists(at: url(for: "\(folder)/\(name).\($0)")) }
        }
        var name = baseName
        var suffix = 2
        while taken(name) {
            name = "\(baseName)_\(suffix)"
            suffix += 1
        }
        return "\(folder)/\(name).\(fileExtension)"
    }

    /// 압축 전 파일의 상대 경로에 대응하는 m4a 상대 경로.
    public static func compressedPath(for workingPath: String) -> String {
        (workingPath as NSString).deletingPathExtension + "." + fileExtension
    }

    /// 압축 중에 쓰는 임시 파일 경로. 끝나면 최종 경로로 옮긴다.
    public static func temporaryCompressedPath(for workingPath: String) -> String {
        (workingPath as NSString).deletingPathExtension + ".converting." + fileExtension
    }

    /// 아직 압축되지 않은 (CAF) 경로인지.
    public static func isWorkingPath(_ relativePath: String) -> Bool {
        (relativePath as NSString).pathExtension.lowercased() == workingExtension
    }

    /// 상대 경로의 실제 위치.
    public func url(for relativePath: String) -> URL {
        root.appending(path: relativePath, directoryHint: .notDirectory)
    }

    /// 파일을 쓰기 전에 과목 폴더를 만든다.
    public func prepareFolder(for relativePath: String) throws {
        try files.createDirectory(at: url(for: relativePath).deletingLastPathComponent())
    }

    /// 파일을 다른 상대 경로로 옮긴다. 대상 폴더는 먼저 만든다.
    public func moveFile(from oldPath: String, to newPath: String) throws {
        try prepareFolder(for: newPath)
        try files.moveItem(at: url(for: oldPath), to: url(for: newPath))
    }

    public func fileExists(at url: URL) -> Bool {
        files.fileExists(at: url)
    }

    /// 앱 밖의 `destination`으로 복사한다.
    public func copyFile(at source: URL, to destination: URL) throws {
        try files.copyItem(at: source, to: destination)
    }

    /// 파일을 지운다. 이미 없으면 지울 것이 없으므로 넘어간다.
    public func removeFile(at relativePath: String) throws {
        let target = url(for: relativePath)
        guard files.fileExists(at: target) else { return }
        try files.removeItem(at: target)
    }
}
