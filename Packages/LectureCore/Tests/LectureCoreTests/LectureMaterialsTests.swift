import Foundation
import Testing
@testable import LectureCore

@Suite struct CanvasFileParsingTests {
    static let filesJSON = """
    [{"id":11,"display_name":"1주차 소개.pdf","content-type":"application/pdf","size":2048,"url":"https://canvas.ssu.ac.kr/files/11/download?verifier=abc"},
     {"id":12,"display_name":"실습 코드.zip","content-type":"application/zip","size":10,"url":"https://canvas.ssu.ac.kr/files/12/download?verifier=abc"},
     {"id":13,"display_name":"2주차.PDF","content-type":"application/octet-stream","size":4096,"url":"https://canvas.ssu.ac.kr/files/13/download?verifier=abc"},
     {"id":14,"display_name":"잠긴 자료.pdf","content-type":"application/pdf","locked_for_user":true,"url":"https://canvas.ssu.ac.kr/files/14/download"},
     {"id":15,"display_name":"주소 없음.pdf","content-type":"application/pdf"},
     {"id":16,"display_name":"http 주소.pdf","content-type":"application/pdf","url":"http://canvas.ssu.ac.kr/files/16/download"}]
    """

    @Test func keepsOnlyDownloadablePDFsAndCountsLocked() throws {
        let list = try CanvasParsing.files(from: Data(Self.filesJSON.utf8))
        #expect(list.files.map(\.id) == [11, 13])
        #expect(list.files.first?.displayName == "1주차 소개.pdf")
        #expect(list.files.first?.size == 2048)
        #expect(list.lockedCount == 3)
    }

    @Test func parsesSingleFileObject() throws {
        let json = #"{"id":21,"display_name":"단일.pdf","content-type":"application/pdf","size":5,"url":"https://canvas.ssu.ac.kr/files/21/download"}"#
        #expect(try CanvasParsing.files(from: Data(json.utf8)).files.map(\.id) == [21])
    }

    @Test func rejectsNonJSON() {
        #expect(throws: CanvasParsingError.self) { try CanvasParsing.files(from: Data("<html>".utf8)) }
    }

    @Test func fileItemIDsTakeOnlyFileItemsWithoutDuplicates() throws {
        let json = #"[{"name":"1주차","items":[{"type":"File","content_id":31},{"type":"ExternalTool","content_id":32},{"type":"File","content_id":31}]},{"name":"2주차","items":[{"type":"File","content_id":33}]}]"#
        #expect(try CanvasParsing.fileItemIDs(fromModules: Data(json.utf8)) == [31, 33])
    }

    @Test func nextPageFromLinkHeader() {
        let header = #"<https://canvas.ssu.ac.kr/api/v1/courses/1/files?page=1>; rel="current", <https://canvas.ssu.ac.kr/api/v1/courses/1/files?page=2&per_page=100>; rel="next", <https://canvas.ssu.ac.kr/api/v1/courses/1/files?page=3>; rel="last""#
        #expect(CanvasParsing.nextPage(fromLinkHeader: header)?.absoluteString == "https://canvas.ssu.ac.kr/api/v1/courses/1/files?page=2&per_page=100")
        #expect(CanvasParsing.nextPage(fromLinkHeader: #"<https://x.example/?page=1>; rel="last""#) == nil)
        #expect(CanvasParsing.nextPage(fromLinkHeader: nil) == nil)
    }
}

@Suite struct CanvasPDFLocatorTests {
    func locator(_ client: FakeCanvasClient) -> CanvasLectureLocator {
        CanvasLectureLocator(client: client, token: "SECRET")
    }

    @Test func followsPagination() async throws {
        let client = FakeCanvasClient()
        client.routes = [
            ("page=2", 200, #"[{"id":2,"display_name":"b.pdf","content-type":"application/pdf","size":1,"url":"https://canvas.ssu.ac.kr/files/2/download"}]"#),
            ("/files?content_types", 200, #"[{"id":1,"display_name":"a.pdf","content-type":"application/pdf","size":1,"url":"https://canvas.ssu.ac.kr/files/1/download"}]"#),
        ]
        client.links = [("/files?content_types", #"<https://canvas.ssu.ac.kr/api/v1/courses/9/files?page=2&per_page=100>; rel="next""#)]
        let list = try await locator(client).pdfFiles(courseID: 9)
        #expect(list.files.map(\.id) == [1, 2])
        #expect(client.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer SECRET")
    }

    @Test func doesNotFollowNextPageOnAnotherHost() async throws {
        let client = FakeCanvasClient()
        client.routes = [("/files?content_types", 200, "[]")]
        client.links = [("/files?content_types", #"<https://evil.example/api/v1/courses/9/files?page=2>; rel="next""#)]
        _ = try await locator(client).pdfFiles(courseID: 9)
        #expect(client.requests.allSatisfy { $0.url?.host == "canvas.ssu.ac.kr" })
    }

    @Test func fallsBackToModuleFileItemsWhenFilesTabIsClosed() async throws {
        let client = FakeCanvasClient()
        client.routes = [
            ("/files?content_types", 403, #"{"errors":[{"message":"disabled"}]}"#),
            ("/modules?include", 200, #"[{"name":"1주차","items":[{"type":"File","content_id":41},{"type":"File","content_id":42}]}]"#),
            ("/files/41", 200, #"{"id":41,"display_name":"강의록.pdf","content-type":"application/pdf","size":3,"url":"https://canvas.ssu.ac.kr/files/41/download"}"#),
        ]
        let list = try await locator(client).pdfFiles(courseID: 9)
        #expect(list.files.map(\.id) == [41])
        #expect(list.failedLookups == 1)
    }

    @Test func emptyFilesTabFallsBackToModuleFileItemsAndExplainsWhenNothingFound() async throws {
        let client = FakeCanvasClient()
        client.routes = [
            ("/files?content_types", 200, "[]"),
            ("/modules?include", 200, #"[{"name":"1주차","items":[{"type":"ExternalTool","title":"강의"},{"type":"ExternalTool","title":"강의2"},{"type":"Page","title":"안내"}]}]"#),
        ]
        let list = try await locator(client).pdfFiles(courseID: 9)
        #expect(list.files.isEmpty)
        #expect(list.note == "파일 메뉴 PDF 0개, 모듈 파일 항목 0개, 과제 첨부 PDF 0개, 모듈 항목 종류: ExternalTool 2, Page 1")

        client.routes = [
            ("/files?content_types", 200, "[]"),
            ("/modules?include", 200, #"[{"name":"1주차","items":[{"type":"File","content_id":51}]}]"#),
            ("/files/51", 200, #"{"id":51,"display_name":"숨은 자료.pdf","content-type":"application/pdf","size":3,"url":"https://canvas.ssu.ac.kr/files/51/download"}"#),
        ]
        #expect(try await locator(client).pdfFiles(courseID: 9).files.map(\.id) == [51])
    }

    @Test func emptyTabWithUnreadableModulesIsNotAnError() async throws {
        let client = FakeCanvasClient()
        client.routes = [("/files?content_types", 200, "[]"), ("/modules?include", 500, "")]
        let list = try await locator(client).pdfFiles(courseID: 9)
        #expect(list.files.isEmpty)
        #expect(list.note.contains("모듈 읽기 실패"))
    }

    @Test func expiredTokenIsReportedAsUnauthorized() async {
        let client = FakeCanvasClient()
        client.routes = [("/files?content_types", 401, ""), ("/modules?include", 401, "")]
        await #expect(throws: CanvasError.unauthorized) { try await locator(client).pdfFiles(courseID: 9) }
    }

    @Test func downloadRequiresRealPDF() async throws {
        let client = FakeCanvasClient()
        let file = CanvasFile(id: 1, displayName: "a.pdf", downloadURL: URL(string: "https://canvas.ssu.ac.kr/files/1/download")!, size: nil)
        client.routes = [("/files/1/download", 200, "%PDF-1.4 fake")]
        #expect(try await locator(client).download(file) == Data("%PDF-1.4 fake".utf8))
        client.routes = [("/files/1/download", 200, "<html>로그인</html>")]
        await #expect(throws: CanvasError.invalidResponse) { try await locator(client).download(file) }
    }
}

@Suite struct LectureMaterialsSyncerTests {
    let files = FakeFileStore()
    let storage: RecordingStorage
    let os = MaterialsSubject(name: "운영체제", semester: "2026년 2학기")

    init() {
        storage = RecordingStorage(root: URL(filePath: "/tmp/LectureRecorderTests/Recordings", directoryHint: .isDirectory), files: files)
    }

    func fileJSON(id: Int, name: String, size: Int) -> String {
        #"{"id":\#(id),"display_name":"\#(name)","content-type":"application/pdf","size":\#(size),"url":"https://canvas.ssu.ac.kr/files/\#(id)/download"}"#
    }

    func client(courses: String = #"[{"id":7,"name":"운영체제 (01분반)"},{"id":8,"name":"기타 교양"}]"#, list: [String]) -> FakeCanvasClient {
        let client = FakeCanvasClient()
        client.routes = [
            ("/api/v1/courses?enrollment_state", 200, courses),
            ("/courses/7/files?content_types", 200, "[" + list.joined(separator: ",") + "]"),
            ("/files/1/download", 200, "%PDF-1 aaaa"),
            ("/files/2/download", 200, "%PDF-1 bbbbbbb"),
            ("/files/3/download", 200, "<html>login</html>"),
        ]
        return client
    }

    func syncer(_ client: FakeCanvasClient) -> LectureMaterialsSyncer {
        LectureMaterialsSyncer(locator: CanvasLectureLocator(client: client, token: "T"), storage: storage, files: files)
    }

    var folder: String { "/tmp/LectureRecorderTests/Recordings/2026년 2학기/운영체제/강의자료" }

    @Test func savesPDFsIntoSubjectMaterialsFolderAndReportsUnmatchedCourses() async throws {
        let c = client(list: [fileJSON(id: 1, name: "1주차.pdf", size: 11)])
        let report = try await syncer(c).sync(subjects: [os])
        #expect(report.downloaded == 1)
        #expect(report.unmatchedCourses == ["기타 교양"])
        #expect(files.written["\(folder)/1주차.pdf"] == Data("%PDF-1 aaaa".utf8))
    }

    @Test func skipsFilesAlreadyDownloadedWithSameSize() async throws {
        let c = client(list: [fileJSON(id: 1, name: "1주차.pdf", size: 11)])
        _ = try await syncer(c).sync(subjects: [os])
        let second = try await syncer(c).sync(subjects: [os])
        #expect(second.downloaded == 0)
        #expect(second.skipped == 1)
        #expect(c.requests.filter { ($0.url?.absoluteString ?? "").contains("/files/1/download") }.count == 1)
    }

    @Test func sameNameDifferentSizeIsKeptSeparatelyWithID() async throws {
        files.add(URL(filePath: "\(folder)/1주차.pdf"))
        files.sizes["\(folder)/1주차.pdf"] = 999
        let c = client(list: [fileJSON(id: 1, name: "1주차.pdf", size: 11)])
        let report = try await syncer(c).sync(subjects: [os])
        #expect(report.downloaded == 1)
        #expect(files.written["\(folder)/1주차 (1).pdf"] != nil)
        #expect(files.sizes["\(folder)/1주차.pdf"] == 999)
    }

    @Test func nonPDFResponseIsReportedAsFailureAndOthersContinue() async throws {
        let c = client(list: [fileJSON(id: 3, name: "가짜.pdf", size: 5), fileJSON(id: 2, name: "진짜.pdf", size: 14)])
        let report = try await syncer(c).sync(subjects: [os])
        #expect(report.failed == ["가짜.pdf"])
        #expect(report.downloaded == 1)
        #expect(files.written["\(folder)/가짜.pdf"] == nil)
    }

    @Test func reportsWhereItLookedForCoursesWithoutPDFs() async throws {
        let c = client(list: [])
        c.routes.insert(("/courses/7/modules?include", 200, #"[{"name":"1주차","items":[{"type":"ExternalTool","title":"강의"}]}]"#), at: 0)
        let report = try await syncer(c).sync(subjects: [os])
        #expect(report.downloaded == 0)
        #expect(report.emptyCourseNotes == ["운영체제: 파일 메뉴 PDF 0개, 모듈 파일 항목 0개, 과제 첨부 PDF 0개, 모듈 항목 종류: ExternalTool 1 / 강의 항목 없음"])
        #expect(report.headline == "받을 PDF를 찾지 못했습니다. PDF를 못 찾은 강의 1개.")
        #expect(report.detailLines.first?.hasPrefix("못 찾음 · 운영체제") == true)
    }

    @Test func tooLargeFileIsNotDownloaded() async throws {
        let c = client(list: [fileJSON(id: 1, name: "큰파일.pdf", size: Int(LectureMaterialsSyncer.maxFileSize) + 1)])
        let report = try await syncer(c).sync(subjects: [os])
        #expect(report.failed == ["큰파일.pdf(너무 큼)"])
        #expect(c.requests.allSatisfy { !($0.url?.absoluteString ?? "").contains("/files/1/download") })
    }

    @Test func lowDiskSpaceFailsWithoutWriting() async throws {
        files.capacity = 5
        let c = client(list: [fileJSON(id: 1, name: "1주차.pdf", size: 11)])
        let report = try await syncer(c).sync(subjects: [os])
        #expect(report.failed == ["1주차.pdf(저장 공간 부족)"])
        #expect(files.written.isEmpty)
    }

    @Test func fileNamesAreSanitized() {
        #expect(LectureMaterialsSyncer.fileName(for: "a/b:c.pdf") == "a-b-c.pdf")
        #expect(LectureMaterialsSyncer.fileName(for: "노트") == "노트.pdf")
        #expect(LectureMaterialsSyncer.fileName(for: "") == "강의자료.pdf")
        #expect(LectureMaterialsSyncer.fileName(for: "x.PDF", id: 5) == "x (5).pdf")
    }

    @Test func summaryMentionsEverything() {
        var report = MaterialsSyncReport()
        report.downloaded = 2
        report.skipped = 1
        report.locked = 3
        report.unmatchedCourses = ["교양"]
        let text = report.summary
        #expect(text.contains("2개를 받았고"))
        #expect(text.contains("잠겨서"))
        #expect(text.contains("교양"))
        #expect(MaterialsSyncReport().summary == "새로 받을 PDF가 없습니다.")
    }

    @Test func materialsFolderPathSitsInsideSubjectFolder() {
        #expect(RecordingStorage.materialsFolderPath(semester: "2026년 2학기", subjectName: "운영체제") == "2026년 2학기/운영체제/강의자료")
        #expect(RecordingStorage.materialsFolderPath(semester: "", subjectName: "운영체제") == "학기 미정/운영체제/강의자료")
    }
}

@Suite struct CommonsDocumentParsingTests {
    static let slidesXML = """
    <content><content_playing_info><content_type>sharedocs</content_type><content_duration>0</content_duration></content_playing_info>
    <service_root><doc><file_uri>https://ssu-toast.commonscdn.com/contents31/x/docs/lec1.pdf?token=SECRET</file_uri>
    <thumb>https://ssu-toast.commonscdn.com/contents31/x/thumb.png</thumb></doc></service_root></content>
    """

    @Test func findsPDFLinksAndOutlineWithoutSecrets() {
        let documents = CanvasParsing.documents(fromContentXML: Self.slidesXML)
        #expect(documents.contentType == "sharedocs")
        #expect(documents.pdfURLs.map(\.lastPathComponent) == ["lec1.pdf"])
        #expect(documents.outline.contains("pdf"))
        #expect(documents.outline.contains("ssu-toast.commonscdn.com"))
        #expect(!documents.outline.contains("SECRET"))
    }

    @Test func noPDFGivesOutlineOnly() {
        let documents = CanvasParsing.documents(fromContentXML: "<content><a/></content>")
        #expect(documents.pdfURLs.isEmpty)
        #expect(documents.outline.contains("태그 content·a"))
    }

    @Test func assignmentFileLinks() throws {
        let modules = #"[{"items":[{"type":"Assignment","content_id":61},{"type":"Assignment","content_id":61},{"type":"File","content_id":9}]}]"#
        #expect(CanvasParsing.assignmentIDs(fromModules: Data(modules.utf8)) == [61])
        let json = #"{"description":"<a href=\"https://canvas.ssu.ac.kr/courses/7/files/71/download?wrap=1\">자료</a> <a href=\"/courses/7/files/72\">b</a> <a href=\"/courses/7/files/71\">c</a>"}"#
        let html = CanvasParsing.assignmentDescription(from: Data(json.utf8))
        #expect(CanvasParsing.fileIDs(inHTML: html) == [71, 72])
        #expect(CanvasParsing.assignmentDescription(from: Data("{}".utf8)) == "")
    }
}

@Suite struct LectureMaterialsSlideSyncTests {
    let files = FakeFileStore()
    let storage: RecordingStorage

    init() {
        storage = RecordingStorage(root: URL(filePath: "/tmp/LectureRecorderTests/Recordings", directoryHint: .isDirectory), files: files)
    }

    func client() -> FakeCanvasClient {
        let client = FakeCanvasClient()
        client.cookies["xn_api_token"] = "LEARNINGX-SECRET"
        client.routes = [
            ("/api/v1/courses?enrollment_state", 200, #"[{"id":7,"name":"운영체제"}]"#),
            ("/courses/7/files?content_types", 403, ""),
            ("/courses/7/modules?include", 200, #"[{"name":"9주차","items":[{"title":"슬라이드","type":"ExternalTool","external_url":"https://canvas.ssu.ac.kr/learningx/lti/lecture_attendance/items/view/981471"}]}]"#),
            ("sessionless_launch?url=", 200, #"{"url":"https://canvas.ssu.ac.kr/courses/7/external_tools/sessionless_launch?verifier=v"}"#),
            ("sessionless_launch?verifier", 200, #"<form action="https://canvas.ssu.ac.kr/learningx/lti/lecture_attendance/items/view/981471" method="post"><input name="a" value="b"></form>"#),
            ("/lecture_attendance/items/view/981471", 200, "<html></html>"),
            ("/attendance_items/981471", 200, #"{"item_content_type":"commons","item_content_data":{"content_id":"abc123"}}"#),
            ("content.php", 200, CommonsDocumentParsingTests.slidesXML),
            ("/docs/lec1.pdf", 200, "%PDF-1 slide"),
        ]
        return client
    }

    @Test func downloadsSlidePDFsFromLearningXItemsWithoutSendingTheCanvasToken() async throws {
        let c = client()
        let syncer = LectureMaterialsSyncer(locator: CanvasLectureLocator(client: c, token: "SECRET"), storage: storage, files: files)
        let subject = MaterialsSubject(name: "운영체제", semester: "2026년 2학기")
        let report = try await syncer.sync(subjects: [subject])
        #expect(report.downloaded == 1)
        #expect(files.written["/tmp/LectureRecorderTests/Recordings/2026년 2학기/운영체제/강의자료/9주차 슬라이드.pdf"] == Data("%PDF-1 slide".utf8))
        let download = try #require(c.request(containing: "/docs/lec1.pdf"))
        #expect(download.value(forHTTPHeaderField: "Authorization") == nil)

        let again = try await syncer.sync(subjects: [subject])
        #expect(again.downloaded == 0)
        #expect(again.skipped == 1)
    }
}
