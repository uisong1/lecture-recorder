import XCTest

extension XCUIApplication {
    /// 테스트용 설정으로 앱을 띄운다.
    static func launchForTesting() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting"]
        app.launch()
        return app
    }

    /// 5초가 안 되는 녹음을 정지하면 뜨는 "너무 짧은 녹음입니다" 창에서 저장을 고른다. 창이 안 뜨면 아무 일도 하지 않는다.
    func keepShortRecordingIfAsked() {
        let keep = buttons["keepShortRecording"]
        if keep.waitForExistence(timeout: 2) { keep.click() }
    }

    /// 설정 창(⌘,)을 열고 탭을 고른다. 설정 창은 마지막 탭을 기억하므로 항상 직접 고른다.
    func openSettings(tab: String) {
        typeKey(",", modifierFlags: .command)
        let button = toolbars.buttons[tab]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.click()
    }
}
