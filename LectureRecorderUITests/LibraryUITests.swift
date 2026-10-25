import XCTest

final class LibraryUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test녹음하면_사이드바_미분류에서_목록으로_보인다() throws {
        let app = XCUIApplication.launchForTesting()

        let button = app.buttons["recordButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.click()
        XCTAssertTrue(app.staticTexts["recordingSubject"].waitForExistence(timeout: 5))
        button.click()
        app.keepShortRecordingIfAsked()
        XCTAssertTrue(app.staticTexts["lastSavedTitle"].waitForExistence(timeout: 5))

        let unclassified = app.descendants(matching: .any)["sidebar-unclassified"].firstMatch
        XCTAssertTrue(unclassified.waitForExistence(timeout: 5))
        unclassified.click()

        let row = app.staticTexts["recordingRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let title = (row.value as? String) ?? row.label
        XCTAssertTrue(title.hasPrefix("미분류"))
    }
}
