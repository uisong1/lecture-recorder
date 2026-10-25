import XCTest

extension XCUIApplication {
    /// 테스트용 설정으로 앱을 띄운다.
    static func launchForTesting() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting"]
        app.launch()
        return app
    }

    /// 설정 창(⌘,)을 열고 탭을 고른다. 설정 창은 마지막 탭을 기억하므로 항상 직접 고른다.
    func openSettings(tab: String) {
        typeKey(",", modifierFlags: .command)
        let button = toolbars.buttons[tab]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.click()
    }
}
