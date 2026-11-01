import Foundation
import Testing
@testable import LectureCore

@Suite struct LMSMediaReportTests {
    func makeReport(_ kind: String, _ url: String, page: String? = "https://player.example.ac.kr/em/1", via: String? = "element") -> LMSMediaReport? {
        var body: [String: Any] = ["kind": kind, "url": url]
        if let page { body["page"] = page }
        if let via { body["via"] = via }
        return LMSMediaReport(body: body)
    }

    @Test func 본편_미디어_보고는_받을_후보가_된다() throws {
        let report = try #require(makeReport("media", "https://cdn.example.ac.kr/c/screen.mp4?token=abc"))

        let candidate = try #require(report.candidate(courseName: "컴퓨터구조 (2150246401)"))
        #expect(candidate.url.absoluteString == "https://cdn.example.ac.kr/c/screen.mp4?token=abc")
        #expect(candidate.referer?.absoluteString == "https://player.example.ac.kr/em/1")
        #expect(candidate.courseName == "컴퓨터구조 (2150246401)")
    }

    @Test func 다른_미디어와_프레임_보고는_후보가_되지_않는다() throws {
        #expect(try #require(makeReport("media", "https://cdn.example.ac.kr/c/preloader.mp4")).candidate(courseName: nil) == nil)
        #expect(try #require(makeReport("media", "blob:https://player.example.ac.kr/uuid")).candidate(courseName: nil) == nil)
        #expect(try #require(makeReport("frame", "https://cdn.example.ac.kr/c/screen.mp4")).candidate(courseName: nil) == nil)
    }

    @Test func 요약에서_쿼리는_빼고_본편은_표시한다() throws {
        let lecture = try #require(makeReport("media", "https://cdn.example.ac.kr/c/screen.mp4?token=secret"))
        #expect(lecture.summary == "미디어: cdn.example.ac.kr/c/screen.mp4 ★본편 (element)")
        #expect(!lecture.summary.contains("secret"))

        let intro = try #require(makeReport("media", "https://cdn.example.ac.kr/c/intro.mp4", via: "fetch"))
        #expect(intro.summary == "미디어: cdn.example.ac.kr/c/intro.mp4 (fetch)")

        let frame = try #require(makeReport("frame", "https://player.example.ac.kr/em/1?x=1", via: "iframe"))
        #expect(frame.summary == "프레임: player.example.ac.kr/em/1 (iframe)")
    }

    @Test func blob_주소는_스트리밍일_수_있다고_알린다() throws {
        let blob = try #require(makeReport("media", "blob:https://player.example.ac.kr/uuid", via: "element"))
        #expect(blob.summary.contains("스트리밍"))
    }

    @Test func 잘못된_보고는_무시한다() {
        #expect(makeReport("other", "https://a.kr/x.mp4") == nil)
        #expect(makeReport("media", "") == nil)
        #expect(LMSMediaReport(body: ["kind": "media"]) == nil)
    }

    @Test func 감지_정보는_중복을_빼고_오래된_것부터_버린다() {
        var diagnostics = LMSDiagnostics()
        diagnostics.record("a")
        diagnostics.record("a")
        #expect(diagnostics.lines == ["a"])
        for index in 0..<(LMSDiagnostics.capacity + 3) { diagnostics.record("줄 \(index)") }
        #expect(diagnostics.lines.count == LMSDiagnostics.capacity)
        #expect(diagnostics.lines.last == "줄 \(LMSDiagnostics.capacity + 2)")
        #expect(!diagnostics.lines.contains("a"))
        diagnostics.clear()
        #expect(diagnostics.lines.isEmpty)
    }
}
