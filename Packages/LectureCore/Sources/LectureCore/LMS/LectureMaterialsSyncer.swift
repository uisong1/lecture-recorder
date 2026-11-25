import Foundation

/// 강의자료를 넣을 앱 과목(이름과 학기).
public struct MaterialsSubject: Equatable, Sendable {
    public let name: String
    public let semester: String

    public init(name: String, semester: String) {
        self.name = name
        self.semester = semester
    }
}

/// "강의자료 가져오기" 결과.
public struct MaterialsSyncReport: Equatable, Sendable {
    public var downloaded = 0
    /// 이미 받아 둔 파일이라 건너뛴 수.
    public var skipped = 0
    /// 받지 못한 파일 이름.
    public var failed: [String] = []
    /// 잠겨 있어 받을 수 없는 PDF 수.
    public var locked = 0
    /// 앱 과목과 이름이 맞지 않아 건너뛴 LMS 강의 이름.
    public var unmatchedCourses: [String] = []
    /// 모듈의 파일 항목 중 열지 못한 수.
    public var unreadableItems = 0
    /// 받을 PDF를 하나도 못 찾은 강의의 설명("강의명: 어디서 몇 개 찾았는지").
    public var emptyCourseNotes: [String] = []
    /// 못 읽은 LMS 강의 이름.
    public var failedCourses: [String] = []

    public init() {}

    /// 결과 한 줄 요약.
    public var headline: String {
        var parts: [String] = []
        if downloaded == 0 && skipped == 0 && failed.isEmpty {
            parts.append(emptyCourseNotes.isEmpty ? "새로 받을 PDF가 없습니다." : "받을 PDF를 찾지 못했습니다.")
        } else {
            parts.append("\(downloaded)개를 받았고 \(skipped)개는 이미 있어 건너뛰었습니다.")
        }
        if !failed.isEmpty { parts.append("\(failed.count)개는 받지 못했습니다.") }
        if !emptyCourseNotes.isEmpty { parts.append("PDF를 못 찾은 강의 \(emptyCourseNotes.count)개.") }
        return parts.joined(separator: " ")
    }

    /// 접어 두는 자세한 내용(줄마다 하나).
    public var detailLines: [String] {
        var lines: [String] = []
        if !failed.isEmpty { lines.append("받지 못한 파일: " + failed.joined(separator: ", ")) }
        if unreadableItems > 0 { lines.append("열지 못한 파일 항목: \(unreadableItems)개") }
        if locked > 0 { lines.append("잠겨서 받을 수 없는 PDF: \(locked)개") }
        lines += emptyCourseNotes.map { "못 찾음 · " + $0 }
        if !failedCourses.isEmpty { lines.append("읽지 못한 강의: " + failedCourses.joined(separator: ", ")) }
        if !unmatchedCourses.isEmpty { lines.append("앱에 같은 이름의 과목이 없어 건너뛴 강의: " + unmatchedCourses.joined(separator: ", ")) }
        return lines
    }

    /// 요약과 자세한 내용을 한 문장으로 합친 것(테스트·로그용).
    public var summary: String { ([headline] + detailLines).joined(separator: " ") }
}

/// Canvas 과목의 PDF 강의자료를 받아 앱 과목의 녹음 폴더 안(`<학기>/<과목>/강의자료/`)에 저장한다.
/// 읽기만 하고 Canvas 데이터는 바꾸지 않는다. 한 번에 하나씩 받고, 이미 받은 파일(같은 이름·같은 크기)은 건너뛴다.
public struct LectureMaterialsSyncer: Sendable {
    /// 파일 하나의 크기 상한. 이보다 큰 PDF는 받지 않는다(메모리·저장 공간 보호).
    public static let maxFileSize: Int64 = 300 * 1_000_000

    private let locator: CanvasLectureLocator
    private let storage: RecordingStorage
    private let files: any FileStoring

    public init(locator: CanvasLectureLocator, storage: RecordingStorage, files: any FileStoring) {
        self.locator = locator
        self.storage = storage
        self.files = files
    }

    /// 과목 이름이 맞는 LMS 강의마다 PDF를 받는다. 한 파일·한 강의가 실패해도 나머지는 계속한다.
    /// 인증 오류(토큰 만료)는 모두 실패하므로 바로 던진다.
    public func sync(subjects: [MaterialsSubject], progress: @Sendable (String) -> Void = { _ in }) async throws -> MaterialsSyncReport {
        var report = MaterialsSyncReport()
        let courses = try await locator.courses()
        for course in courses {
            try Task.checkCancellation()
            guard let name = LMSSubjectMatcher.bestMatch(courseName: course.name, among: subjects.map(\.name)),
                  let subject = subjects.first(where: { $0.name == name })
            else {
                report.unmatchedCourses.append(course.name)
                continue
            }
            progress("\(subject.name) 자료 목록을 읽는 중")
            let found: CanvasFileList
            do {
                found = try await locator.pdfFiles(courseID: course.id)
            } catch CanvasError.unauthorized {
                throw CanvasError.unauthorized
            } catch {
#if canImport(os)
                Log.app.error("LMS 강의자료 목록 실패: \(error.localizedDescription, privacy: .public)")
#endif
                report.failedCourses.append(course.name)
                continue
            }
            var list = found
            if list.files.isEmpty, list.lockedCount == 0 {
                progress("\(subject.name) 슬라이드 항목을 확인하는 중")
                let probe = try await documentFiles(courseID: course.id, progress: progress)
                list.files = probe.files
                if probe.files.isEmpty, !probe.note.isEmpty { list.note += " / " + probe.note }
            }
            if list.files.isEmpty, list.lockedCount == 0, !list.note.isEmpty { report.emptyCourseNotes.append("\(subject.name): \(list.note)") }
            report.locked += list.lockedCount
            report.unreadableItems += list.failedLookups
            let folder = storage.url(for: RecordingStorage.materialsFolderPath(semester: subject.semester, subjectName: subject.name))
            for file in list.files {
                try Task.checkCancellation()
                await save(file, in: folder, subject: subject.name, report: &report, progress: progress)
            }
        }
        return report
    }

    /// 강의 항목(LearningX 슬라이드·문서)에서 PDF 주소를 찾는다. 앞의 몇 개로 먼저 확인해 PDF가 보이면 나머지도 찾고,
    /// 안 보이면 응답 구조 요약만 남긴다. 항목은 하나씩 천천히 열고, 열지 못한 항목은 건너뛴다.
    private func documentFiles(courseID: Int, progress: @Sendable (String) -> Void) async throws -> (files: [CanvasFile], note: String) {
        let items: [CanvasLectureItem]
        do { items = try await locator.lectureItems(courseID: courseID) } catch CanvasError.unauthorized { throw CanvasError.unauthorized } catch { return ([], "") }
        var found: [CanvasFile] = []
        var outline = ""
        var opened = 0
        var documentLike = 0
        var typeCounts: [String: Int] = [:]
        for item in items.prefix(Self.maxDocumentItems) {
            try Task.checkCancellation()
            // 영상이 아닌 항목을 5개 열어도 PDF가 하나도 안 나오면 이 과목은 더 보지 않는다.
            if documentLike >= 5, found.isEmpty { break }
            do {
                let documents = try await locator.documents(courseID: courseID, item: item)
                opened += 1
                typeCounts[documents.contentType.isEmpty ? "?" : documents.contentType, default: 0] += 1
                if documents.isVideo { continue }
                documentLike += 1
                if outline.isEmpty { outline = documents.outline }
                for (offset, url) in documents.pdfURLs.enumerated() {
                    let suffix = documents.pdfURLs.count > 1 ? " \(offset + 1)" : ""
                    found.append(CanvasFile(id: item.itemID * 100 + offset, displayName: "\(item.moduleName) \(item.title)\(suffix)", downloadURL: url, size: nil))
                }
            } catch CanvasError.unauthorized {
                throw CanvasError.unauthorized
            } catch {
                // 보호 표시(DRM)가 있는 항목은 우회하지 않고 건너뛴다. 열지 못한 항목도 건너뛴다.
                continue
            }
        }
        let kinds = typeCounts.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
        let note = items.isEmpty ? "강의 항목 없음" : "LearningX 항목 \(items.count)개 중 \(opened)개 확인(\(kinds.isEmpty ? "없음" : kinds)), PDF 주소 \(found.count)개" + (outline.isEmpty ? "" : " (\(outline))")
        return (found, note)
    }

    /// 한 과목에서 슬라이드·문서 항목을 열어 보는 최대 개수.
    static let maxDocumentItems = 80

    private func save(_ file: CanvasFile, in folder: URL, subject: String, report: inout MaterialsSyncReport, progress: @Sendable (String) -> Void) async {
        let base = Self.fileName(for: file.displayName)
        // 같은 이름에 크기가 다른 파일이 이미 있으면(다른 자료) 번호를 붙여 따로 둔다.
        var destination = folder.appending(path: base, directoryHint: .notDirectory)
        // 크기를 모르는 자료(슬라이드 PDF)는 같은 이름이 있으면 받은 것으로 본다.
        if file.size == nil, files.fileExists(at: destination) {
            report.skipped += 1
            return
        }
        if files.fileExists(at: destination), !Self.sameSize(files.fileSize(at: destination), file.size) {
            destination = folder.appending(path: Self.fileName(for: file.displayName, id: file.id), directoryHint: .notDirectory)
        }
        if files.fileExists(at: destination), Self.sameSize(files.fileSize(at: destination), file.size) {
            report.skipped += 1
            return
        }
        if let size = file.size, size > Self.maxFileSize {
            report.failed.append("\(base)(너무 큼)")
            return
        }
        progress("\(subject): \(base) 받는 중")
        do {
            let data = try await locator.download(file)
            if let free = files.availableCapacity(at: folder.deletingLastPathComponent()), free < Int64(data.count) * 2 {
                report.failed.append("\(base)(저장 공간 부족)")
                return
            }
            if files.fileExists(at: destination) {
                // 크기를 모르는 파일이 이미 있다. 같은 크기일 때만 같은 파일로 본다.
                if files.fileSize(at: destination) == Int64(data.count) {
                    report.skipped += 1
                    return
                }
                destination = folder.appending(path: Self.fileName(for: file.displayName, id: file.id), directoryHint: .notDirectory)
                if files.fileExists(at: destination), files.fileSize(at: destination) == Int64(data.count) {
                    report.skipped += 1
                    return
                }
            }
            try files.createDirectory(at: folder)
            try files.writeData(data, to: destination)
            report.downloaded += 1
        } catch {
#if canImport(os)
            Log.app.error("LMS 강의자료 저장 실패: \(error.localizedDescription, privacy: .public)")
#endif
            if case CanvasError.notPDF(let kind) = error {
                report.failed.append("\(base)(PDF 아님: \(kind))")
            } else {
                report.failed.append(base)
            }
        }
    }

    /// 크기를 모르면(nil) 같다고 보지 않는다.
    static func sameSize(_ onDisk: Int64?, _ expected: Int64?) -> Bool {
        guard let onDisk, let expected else { return false }
        return onDisk == expected
    }

    /// 파일 이름으로 쓸 수 있게 다듬고 `.pdf`를 보장한다. `id`가 있으면 확장자 앞에 붙인다.
    static func fileName(for displayName: String, id: Int? = nil) -> String {
        var stem = RecordingStorage.folderName(for: displayName)
        if stem == RecordingStorage.unclassifiedFolder, displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { stem = "강의자료" }
        if stem.lowercased().hasSuffix(".pdf") { stem = String(stem.dropLast(4)) }
        if let id { stem += " (\(id))" }
        return stem + ".pdf"
    }
}
