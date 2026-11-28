import Foundation

/// 묶음에 담을 북마크 한 개.
public struct BundleBookmark: Sendable, Equatable {
    /// 녹음 안에서의 시점(초).
    public var time: TimeInterval
    public var note: String

    public init(time: TimeInterval, note: String) {
        self.time = time
        self.note = note
    }
}

/// 묶음에 담을 녹음 한 개. DB 모델과 떼어 놓아 파일 시스템만 가짜로 바꿔 테스트할 수 있다.
public struct BundleRecording: Sendable, Equatable {
    public var title: String
    /// nil이면 미분류.
    public var subjectName: String?
    public var semester: String?
    public var startedAt: Date
    public var duration: TimeInterval
    /// 녹음 폴더(`Recordings/`) 기준 상대 경로.
    public var relativePath: String
    /// 수업 전체에 대한 한 줄 메모. 비어 있으면 없는 것이다.
    public var memo: String
    public var bookmarks: [BundleBookmark]
    public var isRecovered: Bool
    /// 전사 문장. nil이면 아직 전사하지 않았다.
    public var transcript: [TranscriptSegment]?
    /// 전사 결과가 있는데 읽지 못했으면 true. 글에 "읽지 못함"으로 적는다.
    public var transcriptUnreadable: Bool

    public init(
        title: String,
        subjectName: String?,
        semester: String? = nil,
        startedAt: Date,
        duration: TimeInterval,
        relativePath: String,
        memo: String = "",
        bookmarks: [BundleBookmark] = [],
        isRecovered: Bool = false,
        transcript: [TranscriptSegment]? = nil,
        transcriptUnreadable: Bool = false
    ) {
        self.title = title
        self.subjectName = subjectName
        self.semester = semester
        self.startedAt = startedAt
        self.duration = duration
        self.relativePath = relativePath
        self.memo = memo
        self.bookmarks = bookmarks
        self.isRecovered = isRecovered
        self.transcript = transcript
        self.transcriptUnreadable = transcriptUnreadable
    }
}

/// 내보내기에 담을 것.
public enum BundleContents: String, CaseIterable, Sendable {
    case both
    case audioOnly
    case transcriptOnly

    public var label: String {
        switch self {
        case .both: "녹음과 전사본"
        case .audioOnly: "녹음만"
        case .transcriptOnly: "전사본만"
        }
    }

    var includesAudio: Bool { self != .transcriptOnly }
    var includesTranscript: Bool { self != .audioOnly }
}

/// 내보내기 작은 창(시안 export-options C)에 보일 문구. 녹음 수와 전사된 수로 정한다.
public struct BundleExportChoices: Equatable, Sendable {
    public let recordingCount: Int
    public let transcriptCount: Int
    /// 전사 결과가 있지만 읽지 못한 녹음 수.
    public let unreadableCount: Int

    public init(recordingCount: Int, transcriptCount: Int, unreadableCount: Int = 0) {
        self.recordingCount = recordingCount
        self.transcriptCount = transcriptCount
        self.unreadableCount = unreadableCount
    }

    /// 선택지 아래 회색 설명 (예: "소리 파일 12개와 전사본 9개").
    public func detail(for contents: BundleContents) -> String {
        let missing = recordingCount - transcriptCount
        switch contents {
        case .both:
            return transcriptCount > 0 ? "소리 파일 \(recordingCount)개와 전사본 \(transcriptCount)개" : "소리 파일 \(recordingCount)개 (전사본은 아직 없어요)"
        case .audioOnly:
            return "소리 파일 \(recordingCount)개"
        case .transcriptOnly:
            if transcriptCount == 0 {
                return unreadableCount > 0 ? "전사 결과를 읽지 못했어요 (전사 탭에서 다시 전사해 주세요)" : "전사한 녹음이 없어요"
            }
            return missing > 0 ? "전사본 \(transcriptCount)개 (전사 안 된 \(missing)개는 빠져요)" : "전사본 \(transcriptCount)개"
        }
    }

    public func isAvailable(_ contents: BundleContents) -> Bool {
        contents != .transcriptOnly || transcriptCount > 0
    }

    /// 내보낸 뒤 알릴 것이 있으면 그 문구. 다 담겼으면 nil.
    public static func notice(for result: RecordingBundleResult) -> String? {
        var parts: [String] = []
        if !result.skippedTitles.isEmpty {
            parts.append("파일이 없어 빠진 녹음: " + result.skippedTitles.joined(separator: ", "))
        }
        if !result.untranscribedTitles.isEmpty {
            parts.append("전사하지 않아 빠진 녹음: " + result.untranscribedTitles.joined(separator: ", "))
        }
        if !result.unreadableTitles.isEmpty {
            parts.append("전사 결과를 읽지 못한 녹음(전사 탭에서 다시 전사해 주세요): " + result.unreadableTitles.joined(separator: ", "))
        }
        guard !parts.isEmpty else { return nil }
        return (["녹음 \(result.exportedCount)개를 내보냈어요."] + parts).joined(separator: "\n")
    }
}

/// 내보내기 결과.
public struct RecordingBundleResult: Sendable, Equatable {
    /// 만들어진 묶음 폴더.
    public let folder: URL
    /// 담긴 녹음 수.
    public let exportedCount: Int
    /// 파일이 없어 담지 못한 녹음의 제목.
    public let skippedTitles: [String]
    /// "전사본만"일 때 아직 전사하지 않아 빠진 녹음의 제목.
    public let untranscribedTitles: [String]
    /// 전사 결과가 있지만 읽지 못해 전사본을 넣지 못한 녹음의 제목.
    public let unreadableTitles: [String]

    public init(folder: URL, exportedCount: Int, skippedTitles: [String], untranscribedTitles: [String] = [], unreadableTitles: [String] = []) {
        self.folder = folder
        self.exportedCount = exportedCount
        self.skippedTitles = skippedTitles
        self.untranscribedTitles = untranscribedTitles
        self.unreadableTitles = unreadableTitles
    }
}

public enum RecordingBundleError: Error, Equatable, LocalizedError {
    case nothingToExport
    case nothingTranscribed
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .nothingToExport: "내보낼 녹음이 없습니다."
        case .nothingTranscribed: "전사한 녹음이 없어요. 전사 탭에서 먼저 전사해 주세요."
        case .failed(let reason): "묶음을 만들지 못했습니다: \(reason)"
        }
    }
}

/// 녹음 파일과 북마크·메모를 정리한 글(`수업 기록.md`), 전사한 녹음의 전사본(`전사/`)을 한 폴더에 묶는다.
/// 사용자가 이 폴더를 직접 Claude 같은 도구에 올려 복습할 수 있게 하는 것이 목적이다.
/// 앱이 외부 서비스를 부르지는 않으며, 원본 녹음은 복사만 하고 건드리지 않는다.
public struct RecordingBundleExporter: Sendable {
    public static let audioFolderName = "녹음"
    public static let summaryFileName = "수업 기록.md"
    public static let transcriptFolderName = "전사"

    private let storage: RecordingStorage
    private let files: any FileStoring
    private let calendar: Calendar

    public init(storage: RecordingStorage, files: any FileStoring = LocalFileStore(), calendar: Calendar = .current) {
        self.storage = storage
        self.files = files
        self.calendar = calendar
    }

    /// `parent` 안에 묶음 폴더를 만들고 녹음을 담는다.
    /// 중간에 실패하면 만들던 폴더를 지워 반쯤 채워진 묶음이 남지 않게 한다.
    /// - Parameter label: 폴더 이름과 글 제목에 쓸 이름 (예: 과목 이름, "모든 녹음").
    /// - Parameter contents: 녹음과 전사본, 녹음만, 전사본만. 전사본만이면 전사하지 않은 녹음은 빠진다.
    public func export(_ recordings: [BundleRecording], label: String, to parent: URL, now: Date, contents: BundleContents = .both) throws -> RecordingBundleResult {
        guard !recordings.isEmpty else { throw RecordingBundleError.nothingToExport }

        var present: [BundleRecording] = []
        var skipped: [String] = []
        var untranscribed: [String] = []
        var unreadable: [String] = []
        for recording in recordings.sorted(by: { $0.startedAt < $1.startedAt }) {
            if contents.includesTranscript, recording.transcriptUnreadable { unreadable.append(recording.title) }
            if contents == .transcriptOnly {
                // 소리 파일은 담지 않으니 파일이 없어도 된다. 전사본이 있어야 한다.
                if Self.hasTranscript(recording) {
                    present.append(recording)
                } else if !recording.transcriptUnreadable {
                    untranscribed.append(recording.title)
                }
            } else if files.fileExists(at: storage.url(for: recording.relativePath)) {
                present.append(recording)
            } else {
                skipped.append(recording.title)
            }
        }
        guard !present.isEmpty else {
            if contents == .transcriptOnly {
                if !unreadable.isEmpty { throw RecordingBundleError.failed("전사 결과를 읽지 못했어요. 전사 탭에서 다시 전사해 주세요.") }
                throw RecordingBundleError.nothingTranscribed
            }
            throw RecordingBundleError.failed("녹음 파일을 찾을 수 없습니다.")
        }

        let folder = availableFolder(label: label, in: parent, now: now)
        do {
            try files.createDirectory(at: folder)
            var entries: [(recording: BundleRecording, fileName: String)] = []
            var usedNames: Set<String> = []
            if contents.includesAudio {
                let audioFolder = folder.appending(path: Self.audioFolderName, directoryHint: .isDirectory)
                try files.createDirectory(at: audioFolder)
                for recording in present {
                    let name = uniqueFileName(for: recording, used: &usedNames)
                    try files.copyItem(at: storage.url(for: recording.relativePath), to: audioFolder.appending(path: name, directoryHint: .notDirectory))
                    entries.append((recording, name))
                }
            } else {
                for recording in present { entries.append((recording, uniqueFileName(for: recording, used: &usedNames))) }
            }
            // 전사한 녹음은 녹음 파일과 같은 이름의 전사본(.md)을 `전사/`에 둔다. 긴 수업도 수업 기록이 길어지지 않게 따로 둔다.
            let transcribed = contents.includesTranscript ? entries.filter { Self.hasTranscript($0.recording) } : []
            if !transcribed.isEmpty {
                let transcriptFolder = folder.appending(path: Self.transcriptFolderName, directoryHint: .isDirectory)
                try files.createDirectory(at: transcriptFolder)
                for entry in transcribed {
                    let text = transcriptMarkdown(for: entry.recording)
                    try files.writeData(Data(text.utf8), to: transcriptFolder.appending(path: Self.transcriptFileName(for: entry.fileName), directoryHint: .notDirectory))
                }
            }
            let text = markdown(entries: entries, label: label, now: now, contents: contents)
            try files.writeData(Data(text.utf8), to: folder.appending(path: Self.summaryFileName, directoryHint: .notDirectory))
        } catch {
            // 반쯤 만든 폴더를 지운다. 지우지 못하면 그 위치를 알려 사용자가 직접 지울 수 있게 한다.
            do {
                try files.removeItem(at: folder)
            } catch let cleanupError {
                Self.logError("반쯤 만든 내보내기 폴더를 지우지 못함 \(folder.path): \(cleanupError.localizedDescription)")
                throw RecordingBundleError.failed("\(error.localizedDescription) (만들다 만 폴더가 남았어요: \(folder.path))")
            }
            throw RecordingBundleError.failed(error.localizedDescription)
        }
        return RecordingBundleResult(
            folder: folder, exportedCount: present.count, skippedTitles: skipped,
            untranscribedTitles: untranscribed, unreadableTitles: unreadable
        )
    }

    /// 빈 문장만 있는 전사는 전사본이 없는 것으로 본다.
    static func hasTranscript(_ recording: BundleRecording) -> Bool {
        !spokenSegments(recording).isEmpty
    }

    /// 글이 있는 문장만, 시각 순서로.
    static func spokenSegments(_ recording: BundleRecording) -> [TranscriptSegment] {
        (recording.transcript ?? [])
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.start < $1.start }
    }

    private static func logError(_ message: String) {
        #if canImport(os)
        Log.storage.error("\(message, privacy: .public)")
        #endif
    }

    // MARK: - 이름

    /// "내보내기 자료구조 2026-10-25". 같은 이름이 있으면 `_2`, `_3` …을 붙인다.
    func availableFolder(label: String, in parent: URL, now: Date) -> URL {
        let base = RecordingStorage.folderName(for: "내보내기 \(RecordingStorage.folderName(for: label)) \(dayText(now))")
        var name = base
        var suffix = 2
        while files.fileExists(at: parent.appending(path: name, directoryHint: .isDirectory)) || files.isDirectory(at: parent.appending(path: name, directoryHint: .isDirectory)) {
            name = "\(base)_\(suffix)"
            suffix += 1
        }
        return parent.appending(path: name, directoryHint: .isDirectory)
    }

    /// "자료구조 2026-03-02 월 10-00.m4a". 겹치면 `_2`를 붙인다.
    func uniqueFileName(for recording: BundleRecording, used: inout Set<String>) -> String {
        let c = calendar.dateComponents([.hour, .minute, .weekday], from: recording.startedAt)
        let weekday = c.weekday.flatMap(Weekday.init(rawValue:))?.shortName ?? ""
        let subject = RecordingStorage.folderName(for: recording.subjectName)
        let base = "\(subject) \(dayText(recording.startedAt)) \(weekday) \(pad(c.hour ?? 0))-\(pad(c.minute ?? 0))"
        let ext = (recording.relativePath as NSString).pathExtension
        func full(_ stem: String) -> String { ext.isEmpty ? stem : "\(stem).\(ext)" }
        var name = full(base)
        var suffix = 2
        while used.contains(name) {
            name = full("\(base)_\(suffix)")
            suffix += 1
        }
        used.insert(name)
        return name
    }

    // MARK: - 글

    /// 묶음을 설명하는 글. 과목별로 묶고, 과목 안에서는 오래된 수업부터 적는다.
    func markdown(entries: [(recording: BundleRecording, fileName: String)], label: String, now: Date, contents: BundleContents = .both) -> String {
        let total = entries.reduce(0) { $0 + $1.recording.duration }
        var lines: [String] = [
            "# 수업 녹음: \(label)",
            "",
            "- 내보낸 날: \(dayText(now))",
            "- 녹음 \(entries.count)개, 총 \(Self.durationText(total))",
        ]
        if contents.includesAudio {
            lines.append("- 녹음 파일은 `\(Self.audioFolderName)/` 폴더에 있습니다. 아래 각 수업의 \"파일\"이 그 이름입니다.")
        }
        if entries.contains(where: { !$0.recording.bookmarks.isEmpty }) {
            lines.append("- 북마크 시각은 녹음 시작부터 잰 시간입니다. 메모는 학생이 수업 중에 직접 적은 것입니다.")
        }
        if contents.includesTranscript {
            lines.append("- 전사한 수업은 `\(Self.transcriptFolderName)/` 폴더에 전사본이 있습니다. 맥에서 자동으로 받아 적은 글이라 틀린 말이 있을 수 있습니다.")
        }

        var order: [String] = []
        var groups: [String: [(recording: BundleRecording, fileName: String)]] = [:]
        for entry in entries {
            let name = (entry.recording.subjectName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let key = name.isEmpty ? RecordingStorage.unclassifiedFolder : name
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(entry)
        }
        for subject in order {
            let items = groups[subject] ?? []
            let semester = items.compactMap { $0.recording.semester?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
            lines += ["", "## \(subject)" + (semester.map { " (\($0))" } ?? "")]
            for (index, item) in items.enumerated() {
                let r = item.recording
                lines += ["", "### \(index + 1). \(r.title)", ""]
                lines.append("- 날짜: \(dateTimeText(r.startedAt))")
                lines.append("- 길이: \(Self.durationText(r.duration))")
                if contents.includesAudio { lines.append("- 파일: `\(Self.audioFolderName)/\(item.fileName)`") }
                let memo = r.memo.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
                if !memo.isEmpty { lines.append("- 수업 메모: \(memo)") }
                if r.isRecovered { lines.append("- 참고: 녹음 중 앱이 꺼져 복구한 녹음이라 끝부분이 없을 수 있습니다.") }
                if contents.includesTranscript {
                    let spoken = Self.spokenSegments(r)
                    if !spoken.isEmpty {
                        lines.append("- 전사: `\(Self.transcriptFolderName)/\(Self.transcriptFileName(for: item.fileName))` (문장 \(spoken.count)개)")
                    } else if r.transcriptUnreadable {
                        lines.append("- 전사: 읽지 못함 (앱의 전사 탭에서 다시 전사해 주세요)")
                    } else {
                        lines.append("- 전사: 없음")
                    }
                }
                // 북마크 기능은 2026-11-29 앱에서 뺐다. 북마크가 있을 때만 적고, 없으면 줄을 쓰지 않는다.
                if !r.bookmarks.isEmpty {
                    lines.append("- 북마크 \(r.bookmarks.count)개:")
                    for bookmark in r.bookmarks.sorted(by: { $0.time < $1.time }) {
                        let note = bookmark.note.split(whereSeparator: \.isNewline).joined(separator: " ")
                            .trimmingCharacters(in: .whitespaces)
                        lines.append("  - \(Self.clockText(bookmark.time)) — \(note.isEmpty ? "(메모 없음)" : note)")
                    }
                }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// "자료구조 2026-03-02 월 10-00.m4a" → "자료구조 2026-03-02 월 10-00.md"
    static func transcriptFileName(for audioFileName: String) -> String {
        let stem = (audioFileName as NSString).deletingPathExtension
        return "\(stem).md"
    }

    /// 녹음 하나의 전사본. 문장마다 녹음 시작부터 잰 시각을 붙인다.
    func transcriptMarkdown(for recording: BundleRecording) -> String {
        var lines = [
            "# 전사: \(recording.title)",
            "",
            "- 날짜: \(dateTimeText(recording.startedAt))",
            "- 길이: \(Self.durationText(recording.duration))",
            "- 맥에서 자동으로 받아 적은 글이라 틀린 말이 있을 수 있습니다. [시각]은 녹음 시작부터 잰 시간입니다.",
            "",
        ]
        for segment in Self.spokenSegments(recording) {
            let text = segment.text.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
            lines.append("[\(Self.clockText(segment.start))] \(text)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func dayText(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(pad(c.month ?? 0))-\(pad(c.day ?? 0))"
    }

    /// "2026-03-02 (월) 10:00"
    private func dateTimeText(_ date: Date) -> String {
        let c = calendar.dateComponents([.hour, .minute, .weekday], from: date)
        let weekday = c.weekday.flatMap(Weekday.init(rawValue:))?.shortName ?? ""
        return "\(dayText(date)) (\(weekday)) \(pad(c.hour ?? 0)):\(pad(c.minute ?? 0))"
    }

    private func pad(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }

    /// 북마크 시점: 한 시간 미만은 "12:34", 이상은 "1:02:03".
    static func clockText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        let mm = minutes < 10 ? "0\(minutes)" : "\(minutes)"
        let ss = secs < 10 ? "0\(secs)" : "\(secs)"
        return hours > 0 ? "\(hours):\(mm):\(ss)" : "\(mm):\(ss)"
    }

    /// 길이: "50분", "1시간 5분", 1분 미만은 "30초".
    static func durationText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return minutes > 0 ? "\(hours)시간 \(minutes)분" : "\(hours)시간" }
        if minutes > 0 { return "\(minutes)분" }
        return "\(total)초"
    }
}
