import Foundation
import Testing
@testable import LectureCore

@Suite struct CanvasParsingTests {
    func data(_ text: String) -> Data { Data(text.utf8) }

    @Test func 과목_목록을_읽고_이름이_없는_과목은_뺀다() throws {
        let json = #"[{"id":48761,"name":"컴퓨터구조 (2150246401)"},{"id":1,"name":"  "},{"id":2},{"id":3,"name":"알고리즘 (2150528504)"}]"#
        let courses = try CanvasParsing.courses(from: data(json))
        #expect(courses == [CanvasCourse(id: 48761, name: "컴퓨터구조 (2150246401)"), CanvasCourse(id: 3, name: "알고리즘 (2150528504)")])
    }

    @Test func JSON이_아니면_오류() {
        #expect(throws: CanvasParsingError.notJSON) { _ = try CanvasParsing.courses(from: data("<html>")) }
        #expect(throws: CanvasParsingError.notJSON) { _ = try CanvasParsing.lectureItems(fromModules: data("{}")) }
        #expect(throws: CanvasParsingError.notJSON) { _ = try CanvasParsing.learningXContent(from: data("[]")) }
    }

    @Test func 모듈에서_LearningX_강의_항목만_모은다() throws {
        let json = """
        [{"name":"2주차","items":[
          {"title":"0911 강의 녹화","type":"ExternalTool","external_url":"https://canvas.ssu.ac.kr/learningx/lti/lecture_attendance/items/view/929093"},
          {"title":"Assignment_1","type":"Assignment","html_url":"https://canvas.ssu.ac.kr/courses/48761/modules/items/3408474"},
          {"title":"외부 링크","type":"ExternalTool","external_url":"https://example.com/other"}
        ]},{"name":"3주차"}]
        """
        let items = try CanvasParsing.lectureItems(fromModules: data(json))
        #expect(items == [CanvasLectureItem(moduleName: "2주차", title: "0911 강의 녹화", itemID: 929093,
                                            launchURL: "https://canvas.ssu.ac.kr/learningx/lti/lecture_attendance/items/view/929093")])
    }

    @Test func 항목_번호는_주소의_숫자만_읽는다() {
        #expect(CanvasParsing.lectureItemID(in: "https://x.kr/learningx/lti/lecture_attendance/items/view/914234?a=1") == 914234)
        #expect(CanvasParsing.lectureItemID(in: "https://x.kr/courses/1/modules/items/3408474") == nil)
        #expect(CanvasParsing.lectureItemID(in: "https://x.kr/lecture_attendance/items/view/") == nil)
    }

    @Test func 실행_주소는_https만_받는다() {
        #expect(CanvasParsing.sessionlessLaunchURL(from: data(#"{"url":"https://canvas.ssu.ac.kr/courses/1/external_tools/sessionless_launch?verifier=x"}"#)) != nil)
        #expect(CanvasParsing.sessionlessLaunchURL(from: data(#"{"url":"http://canvas.ssu.ac.kr/x"}"#)) == nil)
        #expect(CanvasParsing.sessionlessLaunchURL(from: data("{}")) == nil)
    }

    @Test func LTI_양식의_action과_값을_읽는다() throws {
        let html = """
        <html><body onload="document.forms[0].submit()">
        <form action="https://canvas.ssu.ac.kr/learningx/lti/lecture_attendance/items/view/914234" method="post">
          <input type="hidden" name="oauth_nonce" value="a&amp;b">
          <input type='hidden' name='lti_message_type' value='basic-lti-launch-request'>
          <input type="hidden" name="empty">
        </form></body></html>
        """
        let form = try #require(CanvasParsing.ltiForm(from: html, base: URL(string: "https://canvas.ssu.ac.kr/")!))
        #expect(form.action.absoluteString == "https://canvas.ssu.ac.kr/learningx/lti/lecture_attendance/items/view/914234")
        #expect(form.fields.map(\.name) == ["oauth_nonce", "lti_message_type", "empty"])
        #expect(form.fields.map(\.value) == ["a&b", "basic-lti-launch-request", ""])
    }

    @Test func 양식이_없거나_https가_아니면_nil() {
        let base = URL(string: "https://canvas.ssu.ac.kr/")!
        #expect(CanvasParsing.ltiForm(from: "<html>로그인 필요</html>", base: base) == nil)
        #expect(CanvasParsing.ltiForm(from: #"<form action="http://evil.example/x"><input name="a" value="b"></form>"#, base: base) == nil)
    }

    @Test func 상대_주소_action은_기준_주소로_풀어_읽는다() throws {
        let form = try #require(CanvasParsing.ltiForm(from: #"<form action="/launch"><input name="a" value="b"></form>"#, base: URL(string: "https://canvas.ssu.ac.kr/x")!))
        #expect(form.action.absoluteString == "https://canvas.ssu.ac.kr/launch")
    }

    @Test func 항목_상세에서_commons_콘텐츠_번호를_읽는다() throws {
        let json = #"{"item_content_type":"commons","item_content_data":{"content_id":"6a967bcd6cbf5","view_url":"commons.ssu.ac.kr/em/6a967bcd6cbf5"}}"#
        let content = try CanvasParsing.learningXContent(from: data(json))
        #expect(content == LearningXContent(contentType: "commons", contentID: "6a967bcd6cbf5"))
        #expect(content.isCommons)
    }

    @Test func commons가_아니거나_번호가_없으면_commons로_보지_않는다() throws {
        #expect(try !CanvasParsing.learningXContent(from: data(#"{"item_content_type":"pdf"}"#)).isCommons)
        #expect(try !CanvasParsing.learningXContent(from: data(#"{"item_content_type":"commons","item_content_data":{"content_id":""}}"#)).isCommons)
    }

    static let videoXML = """
    <content><content_playing_info><content_id>6ae1ae10f2791</content_id><content_type>video1</content_type>
    <content_duration>2397.31</content_duration></content_playing_info>
    <service_root><media type="default"><main_media></main_media>
    <media_uri method="pseudo"><![CDATA[https://commons.ssu.ac.kr/contents31_pseudo/ssu1000001/6ae1ae10f2791/contents/media_files/mobile/ssmovie.mp4]]></media_uri>
    <media_uri method="progressive" target="all">https://ssuin-object.commonscdn.com/ssu-contents/contents31/ssu1000001/6ae1ae10f2791/contents/media_files/mobile/ssmovie.mp4?token=abc&amp;x=1</media_uri>
    <media_uri method="progressive" target="mobile">https://ssuin-object.commonscdn.com/ssu-contents/contents31/ssu1000001/6ae1ae10f2791/contents/media_files/mobile/ssmovie.mp4?token=abc&amp;x=1</media_uri>
    </media></service_root></content>
    """

    @Test func 영상_응답에서_길이와_mp4_주소를_읽고_영상_서버를_앞에_둔다() {
        let playback = CanvasParsing.playback(fromContentXML: Self.videoXML)
        #expect(playback.contentType == "video1")
        #expect(playback.duration == 2397.31)
        #expect(playback.mp4URLs.count == 2)
        #expect(playback.mp4URLs.first?.host == "ssuin-object.commonscdn.com")
        #expect(playback.mp4URLs.first?.query == "token=abc&x=1")
        #expect(playback.mp4URLs.last?.host == "commons.ssu.ac.kr")
        #expect(!playback.hasProtectionMarker)
        #expect(playback.isDownloadableVideo)
    }

    @Test func 슬라이드_자료는_영상이_아니다() {
        let xml = """
        <content><content_playing_info><content_type>sharedocs</content_type><content_duration>0</content_duration></content_playing_info>
        <service_root><media><media_uri method="progressive">https://ssu-toast.commonscdn.com/contents31/x/contents/media_files/[MEDIA_FILE]</media_uri></media></service_root></content>
        """
        let playback = CanvasParsing.playback(fromContentXML: xml)
        #expect(playback.contentType == "sharedocs")
        #expect(playback.mp4URLs.isEmpty)
        #expect(!playback.isDownloadableVideo)
    }

    @Test func 보호_표시가_있으면_받을_수_없는_영상으로_본다() {
        let xml = Self.videoXML.replacingOccurrences(of: "<media type=\"default\">", with: "<media type=\"default\"><drm type=\"widevine\"/>")
        let playback = CanvasParsing.playback(fromContentXML: xml)
        #expect(playback.hasProtectionMarker)
        #expect(!playback.isDownloadableVideo)
    }

    @Test func 읽을_수_없는_응답은_빈_재생_정보다() {
        let playback = CanvasParsing.playback(fromContentXML: "<html>오류</html>")
        #expect(playback.contentType == "")
        #expect(playback.duration == 0)
        #expect(playback.mp4URLs.isEmpty)
        #expect(!playback.isDownloadableVideo)
    }
}
