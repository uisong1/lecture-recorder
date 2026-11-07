#if canImport(SwiftData)
import Foundation
import SwiftData
import Testing
@testable import LectureCore

final class FakeSkipStore: MissingClassSkipStoring, @unchecked Sendable {
    var skipped: Set<Date> = []
}

@MainActor
@Suite struct LMSBackfillModelTests {
    // 2026-03-02는 월요일. 지금은 3월 6일 금요일 12시.
    let container: ModelContainer
    let files = FakeFileStore()
    let storage: RecordingStorage
    let downloader: FakeLMSDownloader
    let halt = FakeHaltStore()
    let skips = FakeSkipStore()
    let directory: URL
    let os: Subject
    let now = date(2026, 3, 6, 12, 0)
    var context: ModelContext { container.mainContext }

    init() throws {
        container = try LectureModelContainer.make(inMemory: true)
        storage = RecordingStorage(root: URL(filePath: "/tmp/LectureRecorderTests/Recordings", directoryHint: .isDirectory), files: files)
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        os = Subject(name: "운영체제", color: .blue)
        container.mainContext.insert(os)
        let slot = try TimeSlot(weekday: .monday, start: TimeOfDay(hour: 9), end: TimeOfDay(hour: 10, minute: 15), subject: os)
        container.mainContext.insert(slot)
        os.timeSlots.append(slot)
        downloader = FakeLMSDownloader([.data(fakeMP4())])
        let files = files
        downloader.onWrite = { url, data in
            files.add(url)
            files.sizes[url.standardizedFileURL.path] = Int64(data.count)
        }
    }

    func canvasClient(courseName: String = "운영체제 (01분반)", contentXML: String = CanvasParsingTests.videoXML) -> FakeCanvasClient {
        let client = FakeCanvasClient()
        client.cookies["xn_api_token"] = "LEARNINGX-SECRET"
        client.routes = [
            ("/api/v1/courses?enrollment_state", 200, #"[{"id":777,"name":"\#(courseName)"}]"#),
            ("/courses/777/modules?include", 200, #"[{"name":"9주차","items":[{"title":"강의 영상","type":"ExternalTool","external_url":"https://canvas.ssu.ac.kr/learningx/lti/lecture_attendance/items/view/981471"}]}]"#),
            ("sessionless_launch?url=", 200, #"{"url":"https://canvas.ssu.ac.kr/courses/777/external_tools/sessionless_launch?verifier=v"}"#),
            ("sessionless_launch?verifier", 200, #"<form action="https://canvas.ssu.ac.kr/learningx/lti/lecture_attendance/items/view/981471" method="post"><input name="a" value="b"></form>"#),
            ("/lecture_attendance/items/view/981471", 200, "<html></html>"),
            ("/attendance_items/981471", 200, #"{"item_content_type":"commons","item_content_data":{"content_id":"6ae1ae10f2791"}}"#),
            ("content.php", 200, contentXML),
        ]
        return client
    }

    func makeModel(client: FakeCanvasClient? = nil, token: Bool = true, finished: @escaping @MainActor () -> Void = {}) -> LMSBackfillModel {
        let extractor = FakeAudioExtractor(files: files)
        let importer = MediaImporter(context: context, storage: storage, files: files, extractor: extractor, durations: FakeDurationReader(), calendar: seoulCalendar)
        let client = client ?? canvasClient()
        let context = context
        let subjects = [os]
        return LMSBackfillModel(
            fetcher: LMSVideoFetcher(downloader: downloader, sleep: { _ in }),
            importer: importer,
            haltStore: halt,
            skipStore: skips,
            subjects: { subjects },
            recordedStarts: { ((try? context.fetch(FetchDescriptor<Recording>())) ?? []).map(\.startedAt) },
            makeLocator: {
                guard token else { throw CanvasError.noToken }
                return CanvasLectureLocator(client: client, token: "CANVAS-SECRET")
            },
            temporaryDirectory: directory,
            now: { date(2026, 3, 6, 12, 0) },
            calendar: seoulCalendar,
            onFinished: finished
        )
    }

    @Test func 시간표상_수업이_있었는데_녹음이_없는_날을_최근부터_보여준다() {
        let model = makeModel()
        model.reload()
        #expect(model.rows.map(\.start) == [date(2026, 3, 2, 9, 0), date(2026, 2, 23, 9, 0), date(2026, 2, 16, 9, 0), date(2026, 2, 9, 9, 0)])
        #expect(model.rows.allSatisfy { $0.subjectName == "운영체제" })
    }

    @Test func 이미_녹음한_날과_건너뛴_날은_뺀다() {
        context.insert(Recording(title: "녹음", subject: os, startedAt: date(2026, 3, 2, 9, 1), duration: 100, relativePath: "a.m4a"))
        let model = makeModel()
        model.reload()
        #expect(model.rows.first?.start == date(2026, 2, 23, 9, 0))

        model.skip(model.rows[0])
        #expect(model.rows.first?.start == date(2026, 2, 16, 9, 0))
        #expect(skips.skipped == [date(2026, 2, 23, 9, 0)])
    }

    @Test func 수업을_고르면_맞는_LMS_강의의_항목을_불러온다() async {
        let model = makeModel()
        model.reload()
        await model.select(model.rows[0])
        #expect(model.status == .idle)
        #expect(model.choices.map(\.title) == ["강의 영상"])
    }

    @Test func 맞는_LMS_강의가_없으면_알려_준다() async {
        let model = makeModel(client: canvasClient(courseName: "알고리즘"))
        model.reload()
        await model.select(model.rows[0])
        guard case .failed(let message) = model.status else { Issue.record("실패여야 해요"); return }
        #expect(message.contains("운영체제"))
        #expect(model.choices.isEmpty)
    }

    @Test func 토큰이_없으면_알려_준다() async {
        let model = makeModel(token: false)
        model.reload()
        await model.select(model.rows[0])
        #expect(model.status == .failed(CanvasError.noToken.localizedDescription))
    }

    @Test func 항목을_고르면_받아서_그_수업_시작_시각의_녹음으로_넣고_목록에서_뺀다() async throws {
        var finished = 0
        let model = makeModel { finished += 1 }
        model.reload()
        let row = model.rows[0]
        await model.select(row)
        await model.importItem(model.choices[0])

        guard case .done = model.status else { Issue.record("완료여야 해요: \(model.status)"); return }
        let recordings = try context.fetch(FetchDescriptor<Recording>())
        #expect(recordings.count == 1)
        #expect(recordings[0].startedAt == row.start)
        #expect(recordings[0].subject === os)
        #expect(recordings[0].isLMSVideo)
        #expect(!model.rows.contains { $0.start == row.start })
        #expect(model.selected == nil)
        #expect(finished == 1)
        // 받을 때 Range를 쓰지 않고, 영상 서버 주소를 썼다.
        #expect(downloader.requests.first?.url.host == "ssuin-object.commonscdn.com")
    }

    @Test func 암호화_표시가_있으면_멈추고_다시_켜기_전까지_막는다() async {
        let xml = CanvasParsingTests.videoXML.replacingOccurrences(of: "<media type=\"default\">", with: "<media type=\"default\"><drm type=\"widevine\"/>")
        let model = makeModel(client: canvasClient(contentXML: xml))
        model.reload()
        await model.select(model.rows[0])
        await model.importItem(model.choices[0])

        #expect(model.isHalted)
        #expect(halt.isHalted)
        #expect(downloader.requests.isEmpty)

        let before = model.rows.count
        await model.select(model.rows[0])
        #expect(model.choices.isEmpty || model.isHalted)
        model.resumeAfterHalt()
        #expect(!model.isHalted)
        #expect(model.rows.count == before)
    }

    @Test func 슬라이드_항목을_고르면_영상이_아니라고_알린다() async throws {
        let slides = "<content><content_playing_info><content_type>sharedocs</content_type><content_duration>0</content_duration></content_playing_info></content>"
        let model = makeModel(client: canvasClient(contentXML: slides))
        model.reload()
        await model.select(model.rows[0])
        await model.importItem(model.choices[0])
        #expect(model.status == .failed(CanvasError.notVideo.localizedDescription))
        #expect(try context.fetch(FetchDescriptor<Recording>()).isEmpty)
        #expect(!model.isHalted)
    }
}
#endif
