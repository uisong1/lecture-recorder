import Testing
@testable import LectureCore

@Suite struct MenuBarStatusTests {
    @Test func 대기_중에는_시작할_수_있고_다음_과목을_알려준다() {
        let status = MenuBarStatus(isRecording: false, expectedSubjectName: "자료구조")
        #expect(status.icon == .idle)
        #expect(status.headline == "녹음 대기")
        #expect(status.detail == "지금 녹음하면: 자료구조")
        #expect(status.toggleTitle == "녹음 시작")
        #expect(status.canToggle)
        #expect(!status.canBookmark)
        #expect(!status.canPause)
    }

    @Test func 녹음_중에는_과목과_시간을_보이고_정지_북마크가_된다() {
        let status = MenuBarStatus(isRecording: true, subjectName: "자료구조", elapsedText: "12:03", bookmarkCount: 2)
        #expect(status.icon == .recording)
        #expect(status.headline == "녹음 중")
        #expect(status.detail == "자료구조 · 12:03")
        #expect(status.toggleTitle == "녹음 정지")
        #expect(status.canToggle)
        #expect(status.canBookmark)
        #expect(status.canPause)
        #expect(status.pauseTitle == "일시정지")
        #expect(status.bookmarkTitle == "북마크 2")
    }

    @Test func 일시정지_중에는_재개할_수_있고_북마크는_막는다() {
        let status = MenuBarStatus(isRecording: true, isPaused: true, subjectName: "미분류", elapsedText: "01:00")
        #expect(status.icon == .paused)
        #expect(status.headline == "일시정지 중")
        #expect(status.pauseTitle == "재개")
        #expect(status.canPause)
        #expect(!status.canBookmark)
    }

    @Test func 녹음_중이_아니면_일시정지_표시는_무시한다() {
        let status = MenuBarStatus(isRecording: false, isPaused: true)
        #expect(!status.isPaused)
        #expect(status.icon == .idle)
    }

    @Test func 권한이_없으면_시작할_수_없고_안내를_보인다() {
        let status = MenuBarStatus(isRecording: false, isPermissionDenied: true)
        #expect(!status.canToggle)
        #expect(status.permissionNotice != nil)
    }

    @Test func 권한이_없어도_이미_녹음_중이면_정지할_수_있다() {
        let status = MenuBarStatus(isRecording: true, isPermissionDenied: true, subjectName: "x")
        #expect(status.canToggle)
        #expect(status.permissionNotice == nil)
    }

    @Test func 안내할_과목이_없으면_상세_줄이_비어_있다() {
        #expect(MenuBarStatus(isRecording: false).detail == "")
    }
}
