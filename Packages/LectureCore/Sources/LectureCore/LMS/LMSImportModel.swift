#if canImport(SwiftData)
import Foundation
import Observation

/// 암호화·DRM이 나타나 LMS 가져오기를 멈췄는지 기억한다. 다시 켜는 것은 사용자만 한다.
public protocol LMSHaltStoring: AnyObject, Sendable {
    var isHalted: Bool { get set }
}

public final class UserDefaultsLMSHaltStore: LMSHaltStoring, @unchecked Sendable {
    public static let key = "lmsHaltedForProtection"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var isHalted: Bool {
        get { defaults.bool(forKey: Self.key) }
        set { defaults.set(newValue, forKey: Self.key) }
    }
}

/// LMS 창 아래의 "이 영상 가져오기" 상태. 웹뷰가 영상 주소를 알려 주면 후보를 잡고, 버튼을 누르면 받아서 녹음 목록에 넣는다.
@MainActor
@Observable
public final class LMSImportModel {
    public enum Status: Equatable {
        case idle
        case downloading(Double)
        case importing
        case done(String)
        case failed(String)
    }

    public static let keepVideoDefaultsKey = "lmsKeepVideo"

    public private(set) var candidate: LMSVideoCandidate?
    public private(set) var status: Status = .idle
    /// 강의명. 웹 페이지에서 읽은 값으로 시작하고 사용자가 고칠 수 있다.
    public private(set) var courseName = ""
    public private(set) var subject: Subject?
    /// 사용자가 직접 고른 날짜. nil이면 서버가 알려 준 영상 파일 날짜를, 그것도 없으면 오늘을 쓴다.
    public var customDate: Date?
    public private(set) var isHalted: Bool

    private var subjectEditedByUser = false
    private let fetcher: LMSVideoFetcher
    private let importer: MediaImporter
    private let haltStore: any LMSHaltStoring
    private let subjects: @MainActor () -> [Subject]
    private let cookieHeader: @MainActor (URL) async -> String?
    private let keepVideo: @MainActor () -> Bool
    private let temporaryDirectory: URL
    private let now: () -> Date
    private let onFinished: @MainActor () -> Void

    public init(
        fetcher: LMSVideoFetcher,
        importer: MediaImporter,
        haltStore: any LMSHaltStoring,
        subjects: @escaping @MainActor () -> [Subject],
        cookieHeader: @escaping @MainActor (URL) async -> String?,
        keepVideo: @escaping @MainActor () -> Bool = { false },
        temporaryDirectory: URL = FileManager.default.temporaryDirectory.appending(path: "LectureRecorder/LMS", directoryHint: .isDirectory),
        now: @escaping () -> Date = { Date() },
        onFinished: @escaping @MainActor () -> Void = {}
    ) {
        self.fetcher = fetcher
        self.importer = importer
        self.haltStore = haltStore
        self.subjects = subjects
        self.cookieHeader = cookieHeader
        self.keepVideo = keepVideo
        self.temporaryDirectory = temporaryDirectory
        self.now = now
        self.onFinished = onFinished
        isHalted = haltStore.isHalted
    }

    public var isBusy: Bool {
        switch status {
        case .downloading, .importing: true
        default: false
        }
    }

    public var canImport: Bool { candidate != nil && !isBusy && !isHalted }

    /// 웹뷰가 본편 영상 주소를 알려 줬다. 같은 영상이면 사용자가 고친 값을 지우지 않는다.
    public func captured(_ new: LMSVideoCandidate) {
        guard !isHalted, !isBusy else { return }
        if candidate?.url == new.url {
            candidate = new
            if courseName.isEmpty, let name = new.courseName { editCourseName(name) }
            return
        }
        candidate = new
        status = .idle
        customDate = nil
        subjectEditedByUser = false
        courseName = new.courseName ?? ""
        subject = suggestedSubject()
    }

    /// 강의명이 바뀌었거나 영상 페이지를 떠났다.
    public func clearCandidate() {
        guard !isBusy else { return }
        candidate = nil
        if case .done = status {} else { status = .idle }
    }

    public func resumeAfterHalt() {
        haltStore.isHalted = false
        isHalted = false
        status = .idle
    }

    /// 사용자가 강의명을 고쳤다. 과목을 직접 고르기 전까지는 새 강의명으로 과목을 다시 추천한다.
    public func editCourseName(_ name: String) {
        courseName = name
        if !subjectEditedByUser { subject = suggestedSubject() }
    }

    /// 사용자가 과목을 직접 골랐다. 이후에는 강의명이 바뀌어도 과목을 바꾸지 않는다.
    public func editSubject(_ new: Subject?) {
        subject = new
        subjectEditedByUser = true
    }

    private func suggestedSubject() -> Subject? {
        let all = subjects()
        guard let name = LMSSubjectMatcher.bestMatch(courseName: courseName, among: all.map(\.name)) else { return nil }
        return all.first { $0.name == name }
    }

    /// 영상을 받아 녹음 목록에 넣는다.
    public func importCurrent() async {
        guard canImport, let candidate else { return }
        status = .downloading(0)
        let fileManager = FileManager.default
        let temporary = temporaryDirectory.appending(path: "\(UUID().uuidString).mp4")
        defer { try? fileManager.removeItem(at: temporary) }
        do {
            try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
            let header = await cookieHeader(candidate.url)
            let request = LMSDownloadRequest(url: candidate.url, referer: candidate.referer, cookieHeader: header)
            let model = self
            let result = try await fetcher.fetch(request, to: temporary) { fraction in
                Task { @MainActor in
                    if case .downloading = model.status { model.status = .downloading(fraction) }
                }
            }
            status = .importing
            let startedAt = customDate ?? result.lastModified ?? now()
            let recording = try await importer.importFile(
                at: temporary,
                subject: subject,
                startedAt: startedAt,
                keepVideo: keepVideo(),
                isLMSVideo: true
            )
            status = .done(recording.title)
            onFinished()
        } catch LMSFetchError.protectedContent {
            // 우회하지 않고 멈춘다. 사용자가 직접 다시 켤 때까지 가져오기를 막는다.
            haltStore.isHalted = true
            isHalted = true
            status = .failed(LMSFetchError.protectedContent.localizedDescription)
            Log.app.error("LMS 영상이 암호화·스트리밍 형식이라 가져오기를 멈춤")
        } catch {
            Log.app.error("LMS 영상 가져오기 실패: \(error.localizedDescription, privacy: .public)")
            status = .failed(error.localizedDescription)
        }
    }
}
#endif
