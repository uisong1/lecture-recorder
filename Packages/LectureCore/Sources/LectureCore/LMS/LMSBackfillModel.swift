#if canImport(SwiftData)
import Foundation
import Observation
import SwiftData

/// 시간표상 수업이 있었는데 녹음이 없는 날 한 줄.
public struct MissingClassRow: Identifiable, Equatable, Sendable {
    public let subjectID: PersistentIdentifier
    public let subjectName: String
    public let start: Date
    public let end: Date

    public var id: String { "\(subjectName)|\(start.timeIntervalSince1970)" }

    public init(subjectID: PersistentIdentifier, subjectName: String, start: Date, end: Date) {
        self.subjectID = subjectID
        self.subjectName = subjectName
        self.start = start
        self.end = end
    }
}

/// 사용자가 "휴강·불필요"로 표시한 수업(시작 시각)을 기억한다.
public protocol MissingClassSkipStoring: AnyObject, Sendable {
    var skipped: Set<Date> { get set }
}

public final class UserDefaultsMissingClassSkipStore: MissingClassSkipStoring, @unchecked Sendable {
    public static let key = "lmsBackfillSkippedClasses"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var skipped: Set<Date> {
        get { Set((defaults.array(forKey: Self.key) as? [Double] ?? []).map { Date(timeIntervalSince1970: $0) }) }
        set { defaults.set(newValue.map(\.timeIntervalSince1970).sorted(), forKey: Self.key) }
    }
}

/// "녹음 없는 수업일" 목록과, 날짜를 골라 LMS 영상의 소리를 그 수업 녹음으로 채우는 흐름.
/// 영상을 어느 항목으로 채울지는 사용자가 고른다(영상에는 수업 날짜가 없다). 암호화·DRM이 보이면 우회하지 않고 멈춘다.
@MainActor
@Observable
public final class LMSBackfillModel {
    public enum Status: Equatable {
        case idle
        case loadingItems
        case working(String)
        case done(String)
        case failed(String)
    }

    public private(set) var rows: [MissingClassRow] = []
    public private(set) var selected: MissingClassRow?
    /// 고른 수업의 LMS 과목에 있는 주차별 강의 항목. 영상인지는 가져올 때 확인한다.
    public private(set) var choices: [CanvasLectureItem] = []
    public private(set) var status: Status = .idle
    public private(set) var isHalted: Bool

    /// 최근 며칠 안의 빠진 수업만 본다.
    public static let daysBack = 28

    private var courses: [CanvasCourse]?
    private var matchedCourseID: Int?
    private let fetcher: LMSVideoFetcher
    private let importer: MediaImporter
    private let haltStore: any LMSHaltStoring
    private let skipStore: any MissingClassSkipStoring
    private let subjects: @MainActor () -> [Subject]
    private let recordedStarts: @MainActor () -> [Date]
    private let makeLocator: @MainActor () throws -> CanvasLectureLocator
    private let keepVideo: @MainActor () -> Bool
    private let temporaryDirectory: URL
    private let now: () -> Date
    private let calendar: Calendar
    private let onFinished: @MainActor () -> Void

    public init(
        fetcher: LMSVideoFetcher,
        importer: MediaImporter,
        haltStore: any LMSHaltStoring,
        skipStore: any MissingClassSkipStoring,
        subjects: @escaping @MainActor () -> [Subject],
        recordedStarts: @escaping @MainActor () -> [Date],
        makeLocator: @escaping @MainActor () throws -> CanvasLectureLocator,
        keepVideo: @escaping @MainActor () -> Bool = { false },
        temporaryDirectory: URL = FileManager.default.temporaryDirectory.appending(path: "LectureRecorder/LMSBackfill", directoryHint: .isDirectory),
        now: @escaping () -> Date = { Date() },
        calendar: Calendar = .current,
        onFinished: @escaping @MainActor () -> Void = {}
    ) {
        self.fetcher = fetcher
        self.importer = importer
        self.haltStore = haltStore
        self.skipStore = skipStore
        self.subjects = subjects
        self.recordedStarts = recordedStarts
        self.makeLocator = makeLocator
        self.keepVideo = keepVideo
        self.temporaryDirectory = temporaryDirectory
        self.now = now
        self.calendar = calendar
        self.onFinished = onFinished
        isHalted = haltStore.isHalted
    }

    public var isBusy: Bool {
        switch status {
        case .loadingItems, .working: true
        default: false
        }
    }

    /// 시간표와 녹음을 다시 읽어 빠진 수업 목록을 만든다.
    public func reload() {
        var schedule = ClassSchedule<PersistentIdentifier>()
        let all = subjects()
        for subject in all {
            for slot in subject.timeSlots {
                guard let period = slot.period else { continue }
                try? schedule.add(.init(period: period, subjectID: subject.persistentModelID))
            }
        }
        let names = Dictionary(all.map { ($0.persistentModelID, $0.name) }, uniquingKeysWith: { first, _ in first })
        rows = schedule.missingClasses(
            recordedStarts: recordedStarts(),
            skipped: skipStore.skipped,
            now: now(),
            daysBack: Self.daysBack,
            calendar: calendar
        ).map { MissingClassRow(subjectID: $0.subjectID, subjectName: names[$0.subjectID] ?? "", start: $0.start, end: $0.end) }
        if let selected, !rows.contains(selected) { clearSelection() }
    }

    /// "휴강·불필요"로 표시해 목록에서 뺀다.
    public func skip(_ row: MissingClassRow) {
        var skipped = skipStore.skipped
        skipped.insert(row.start)
        skipStore.skipped = skipped
        reload()
    }

    public func clearSelection() {
        guard !isBusy else { return }
        selected = nil
        choices = []
        matchedCourseID = nil
        status = .idle
    }

    public func resumeAfterHalt() {
        haltStore.isHalted = false
        isHalted = false
        status = .idle
    }

    /// 수업을 골랐다. 그 과목에 맞는 LMS 강의의 주차별 항목을 불러온다.
    public func select(_ row: MissingClassRow) async {
        guard !isBusy, !isHalted else { return }
        selected = row
        choices = []
        matchedCourseID = nil
        status = .loadingItems
        do {
            let locator = try makeLocator()
            if courses == nil { courses = try await locator.courses() }
            let matches = (courses ?? []).filter { LMSSubjectMatcher.bestMatch(courseName: $0.name, among: [row.subjectName]) != nil }
            guard let course = matches.first else {
                status = .failed("‘\(row.subjectName)’에 맞는 LMS 강의를 찾지 못했어요. 과목 이름이 LMS 강의명과 다를 수 있어요.")
                return
            }
            matchedCourseID = course.id
            choices = try await locator.lectureItems(courseID: course.id)
            status = choices.isEmpty ? .failed("이 강의에 강의 항목이 없어요.") : .idle
        } catch {
            Log.app.error("LMS 강의 항목 불러오기 실패: \(error.localizedDescription, privacy: .public)")
            status = .failed(error.localizedDescription)
        }
    }

    /// 고른 항목의 영상 소리를 받아 선택한 수업의 녹음으로 넣는다.
    public func importItem(_ item: CanvasLectureItem) async {
        guard !isBusy, !isHalted, let row = selected, let courseID = matchedCourseID else { return }
        status = .working("영상을 확인하는 중")
        let fileManager = FileManager.default
        let temporary = temporaryDirectory.appending(path: "\(UUID().uuidString).mp4")
        defer { try? fileManager.removeItem(at: temporary) }
        do {
            try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
            let playback = try await makeLocator().playback(courseID: courseID, item: item)
            guard let url = playback.mp4URLs.first else { throw CanvasError.notVideo }
            status = .working("영상을 받는 중")
            let request = LMSDownloadRequest(url: url, referer: URL(string: "https://commons.ssu.ac.kr/"), cookieHeader: nil)
            _ = try await fetcher.fetch(request, to: temporary)
            status = .working("소리를 추출하는 중")
            let subject = subjects().first { $0.persistentModelID == row.subjectID }
            let recording = try await importer.importFile(
                at: temporary,
                subject: subject,
                startedAt: row.start,
                title: nil,
                keepVideo: keepVideo(),
                isLMSVideo: true
            )
            status = .done(recording.title)
            clearSelectionAfterImport()
            onFinished()
        } catch CanvasError.protectedContent {
            halt(reason: CanvasError.protectedContent.localizedDescription)
        } catch LMSFetchError.protectedContent {
            halt(reason: LMSFetchError.protectedContent.localizedDescription)
        } catch {
            Log.app.error("LMS 영상 채우기 실패: \(error.localizedDescription, privacy: .public)")
            status = .failed(error.localizedDescription)
        }
    }

    private func clearSelectionAfterImport() {
        let message = status
        selected = nil
        choices = []
        matchedCourseID = nil
        reload()
        status = message
    }

    private func halt(reason: String) {
        // 우회하지 않고 멈춘다. 사용자가 직접 다시 켤 때까지 막는다.
        haltStore.isHalted = true
        isHalted = true
        status = .failed(reason)
        Log.app.error("LMS 영상이 암호화·보호 형식이라 채우기를 멈춤")
    }
}
#endif
