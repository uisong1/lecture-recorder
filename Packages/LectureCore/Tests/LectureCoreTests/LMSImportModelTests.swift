#if canImport(SwiftData)
import Foundation
import SwiftData
import Testing
@testable import LectureCore

final class FakeHaltStore: LMSHaltStoring, @unchecked Sendable {
    var isHalted = false
}

@MainActor
@Suite struct LMSImportModelTests {
    let container: ModelContainer
    let files = FakeFileStore()
    let storage: RecordingStorage
    let downloader: FakeLMSDownloader
    let halt = FakeHaltStore()
    let directory: URL
    let os: Subject
    let ds: Subject
    var context: ModelContext { container.mainContext }

    let video = URL(string: "https://cdn.example.ac.kr/lecture/screen.mp4")!

    init() throws { try self.init(outcomes: [.data(fakeMP4())]) }

    init(outcomes: [FakeLMSDownloader.Outcome]) throws {
        container = try LectureModelContainer.make(inMemory: true)
        storage = RecordingStorage(root: URL(filePath: "/tmp/LectureRecorderTests/Recordings", directoryHint: .isDirectory), files: files)
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        os = Subject(name: "운영체제", color: .blue)
        ds = Subject(name: "자료구조", color: .green)
        container.mainContext.insert(os)
        container.mainContext.insert(ds)
        downloader = FakeLMSDownloader(outcomes)
        let files = files
        downloader.onWrite = { url, data in
            files.add(url)
            files.sizes[url.standardizedFileURL.path] = Int64(data.count)
        }
    }

    func makeModel(keepVideo: Bool = false, finished: @escaping @MainActor () -> Void = {}) -> LMSImportModel {
        let extractor = FakeAudioExtractor(files: files)
        let importer = MediaImporter(context: context, storage: storage, files: files, extractor: extractor, durations: FakeDurationReader(), calendar: seoulCalendar)
        let subjects = [os, ds]
        return LMSImportModel(
            fetcher: LMSVideoFetcher(downloader: downloader, sleep: { _ in }),
            importer: importer,
            haltStore: halt,
            subjects: { subjects },
            cookieHeader: { _ in "session=abc" },
            keepVideo: { keepVideo },
            temporaryDirectory: directory,
            now: { date(2026, 11, 2, 9, 0) },
            onFinished: finished
        )
    }

    func candidate(course: String? = "운영체제 (01분반)") -> LMSVideoCandidate {
        LMSVideoCandidate(url: video, referer: URL(string: "https://lms.example.ac.kr/viewer"), courseName: course)
    }

    @Test func 영상을_잡으면_강의명으로_과목을_추천한다() {
        let model = makeModel()
        model.captured(candidate())

        #expect(model.canImport)
        #expect(model.courseName == "운영체제 (01분반)")
        #expect(model.subject === os)
    }

    @Test func 사용자가_고른_과목은_강의명이_바뀌어도_유지한다() {
        let model = makeModel()
        model.captured(candidate())
        model.editSubject(ds)
        model.editCourseName("운영체제 보강")

        #expect(model.subject === ds)
    }

    @Test func 같은_영상이_다시_잡혀도_고친_값을_지우지_않는다() {
        let model = makeModel()
        model.captured(candidate())
        model.editCourseName("자료구조 보강")
        model.customDate = date(2026, 10, 30, 10, 0)
        model.captured(candidate())

        #expect(model.courseName == "자료구조 보강")
        #expect(model.customDate == date(2026, 10, 30, 10, 0))
        #expect(model.subject === ds)
    }

    @Test func 가져오면_쿠키와_referer로_받아_녹음_목록에_넣고_LMS_표시를_남긴다() async throws {
        var finished = 0
        let model = makeModel { finished += 1 }
        model.captured(candidate())

        await model.importCurrent()

        let request = try #require(downloader.requests.first)
        #expect(request.url == video)
        #expect(request.referer?.absoluteString == "https://lms.example.ac.kr/viewer")
        #expect(request.cookieHeader == "session=abc")
        let recording = try #require(try context.fetch(FetchDescriptor<Recording>()).first)
        #expect(recording.isLMSVideo)
        #expect(recording.subject === os)
        #expect(recording.videoRelativePath == nil)
        #expect(model.status == .done(recording.title))
        #expect(finished == 1)
        // 받은 임시 파일은 남기지 않는다.
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(leftovers.filter { $0.hasSuffix(".mp4") }.isEmpty)
    }

    @Test func 날짜는_고른_날짜_다음_서버_날짜_마지막으로_오늘을_쓴다() async throws {
        let served = date(2026, 10, 20, 18, 0)
        let model = makeModel()
        model.captured(candidate())
        await model.importCurrent()
        // 서버 날짜가 없어서 오늘로 들어간다.
        #expect(try context.fetch(FetchDescriptor<Recording>()).map(\.startedAt) == [date(2026, 11, 2, 9, 0)])

        let withServer = try LMSImportModelTests(outcomes: [.data(fakeMP4(), lastModified: served)])
        let second = withServer.makeModel()
        second.captured(withServer.candidate())
        await second.importCurrent()
        #expect(try withServer.context.fetch(FetchDescriptor<Recording>()).map(\.startedAt) == [served])

        let custom = try LMSImportModelTests(outcomes: [.data(fakeMP4(), lastModified: served)])
        let third = custom.makeModel()
        third.captured(custom.candidate())
        third.customDate = date(2026, 10, 29, 13, 0)
        await third.importCurrent()
        #expect(try custom.context.fetch(FetchDescriptor<Recording>()).map(\.startedAt) == [date(2026, 10, 29, 13, 0)])
    }

    @Test func 영상도_보관을_켜면_영상_파일이_소리_파일_옆에_남는다() async throws {
        let model = makeModel(keepVideo: true)
        model.captured(candidate())

        await model.importCurrent()

        let recording = try #require(try context.fetch(FetchDescriptor<Recording>()).first)
        let videoPath = try #require(recording.videoRelativePath)
        #expect(videoPath.hasSuffix(".mp4"))
        #expect((videoPath as NSString).deletingPathExtension == (recording.relativePath as NSString).deletingPathExtension)
        #expect(files.fileExists(at: storage.url(for: videoPath)))
    }

    @Test func 로그인이_만료되면_알리고_녹음을_만들지_않는다() async throws {
        let test = try LMSImportModelTests(outcomes: [.failure(.httpStatus(403))])
        let model = test.makeModel()
        model.captured(test.candidate())

        await model.importCurrent()

        guard case .failed(let message) = model.status else { Issue.record("실패 상태가 아님"); return }
        #expect(message.contains("로그인"))
        #expect(try test.context.fetch(FetchDescriptor<Recording>()).isEmpty)
        #expect(!model.isHalted)
    }

    @Test func 암호화된_영상이면_기능을_멈추고_사용자가_다시_켤_때까지_막는다() async throws {
        let test = try LMSImportModelTests(outcomes: [.data(fakeMP4(moovContent: "trakcenc"))])
        let model = test.makeModel()
        model.captured(test.candidate())

        await model.importCurrent()

        #expect(model.isHalted)
        #expect(test.halt.isHalted)
        #expect(!model.canImport)
        #expect(try test.context.fetch(FetchDescriptor<Recording>()).isEmpty)
        // 멈춘 동안에는 새 영상을 잡지 않는다.
        model.captured(test.candidate())
        #expect(test.downloader.requests.count == 1)

        model.resumeAfterHalt()
        #expect(!test.halt.isHalted)
    }

    @Test func 멈춘_상태로_저장돼_있으면_앱을_다시_켜도_멈춰_있다() {
        halt.isHalted = true
        let model = makeModel()
        model.captured(candidate())
        #expect(model.isHalted)
        #expect(!model.canImport)
    }
}

@MainActor
@Suite struct RecordingLMSRestrictionTests {
    let container: ModelContainer
    let files = FakeFileStore()
    let storage: RecordingStorage
    var context: ModelContext { container.mainContext }

    init() throws {
        container = try LectureModelContainer.make(inMemory: true)
        storage = RecordingStorage(root: URL(filePath: "/tmp/LectureRecorderTests/Recordings", directoryHint: .isDirectory), files: files)
    }

    func addRecording(_ path: String, lms: Bool, video: String? = nil) -> Recording {
        let recording = Recording(title: "보강", subject: nil, startedAt: date(2026, 3, 2, 10, 0), duration: 60, relativePath: path)
        recording.isLMSVideo = lms
        recording.videoRelativePath = video
        context.insert(recording)
        files.add(storage.url(for: path))
        if let video { files.add(storage.url(for: video)) }
        return recording
    }

    @Test func LMS_영상은_공유와_다른_곳에_저장을_막는다() throws {
        let lms = addRecording("미분류/a.m4a", lms: true)
        let own = addRecording("미분류/b.m4a", lms: false)
        let manager = RecordingManager(context: context, storage: storage)

        #expect(!manager.canShare(lms))
        #expect(manager.shareURL(for: lms) == nil)
        #expect(throws: RecordingManagerError.sharingRestricted) { try manager.export(lms, to: URL(filePath: "/tmp/out.m4a")) }
        #expect(manager.canShare(own))
        #expect(manager.shareURL(for: own) != nil)
    }

    @Test func 묶음_내보내기에서_LMS_영상은_빠진다() throws {
        let lms = addRecording("미분류/a.m4a", lms: true)
        let own = addRecording("미분류/b.m4a", lms: false)
        let manager = RecordingManager(context: context, storage: storage)
        let parent = URL(filePath: "/tmp/내보내기", directoryHint: .isDirectory)

        let result = try manager.exportBundle([lms, own], label: "모든 녹음", to: parent, now: date(2026, 10, 25, 9, 0), calendar: seoulCalendar)

        #expect(result.exportedCount == 1)
        #expect(throws: RecordingBundleError.nothingToExport) {
            try manager.exportBundle([lms], label: "LMS", to: parent, now: date(2026, 10, 25, 9, 0), calendar: seoulCalendar)
        }
    }

    @Test func 과목을_옮기면_함께_보관한_영상도_따라간다() throws {
        let subject = try SubjectManager(context: context).add(name: "운영체제", color: .blue)
        let recording = addRecording("미분류/a.m4a", lms: true, video: "미분류/a.mp4")
        let manager = RecordingManager(context: context, storage: storage)

        try manager.move(recording, to: subject)

        let video = try #require(recording.videoRelativePath)
        #expect(video.hasSuffix(".mp4"))
        #expect(video.hasPrefix(RecordingStorage.folderPath(semester: subject.semester, subjectName: subject.name)))
        #expect(files.fileExists(at: storage.url(for: video)))
        #expect(!files.fileExists(at: storage.url(for: "미분류/a.mp4")))
    }

    @Test func 휴지통으로_보내면_영상도_함께_간다() throws {
        let recording = addRecording("미분류/a.m4a", lms: true, video: "미분류/a.mp4")
        let manager = RecordingManager(context: context, storage: storage)

        try manager.trash(recording)

        #expect(files.trashed.contains { $0.hasSuffix("a.m4a") })
        #expect(files.trashed.contains { $0.hasSuffix("a.mp4") })
    }
}
#endif
