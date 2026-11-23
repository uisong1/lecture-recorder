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
        #expect(client.requests.count == 1)
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
