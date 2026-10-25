import XCTest

final class ScheduleSettingsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test시간표를_추가하고_겹치면_오류가_보인다() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting"]
        app.launch()
        app.typeKey(",", modifierFlags: .command)

        let nameField = app.textFields["newSubjectName"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.click()
        nameField.typeText("자료구조\r")

        app.toolbars.buttons["시간표"].click()
        let subjectPicker = app.popUpButtons["slotSubject"]
        XCTAssertTrue(subjectPicker.waitForExistence(timeout: 5))
        subjectPicker.click()
        app.menuItems["자료구조"].click()

        // 기본값: 월 09:00–10:15
        app.buttons["addSlot"].click()
        XCTAssertTrue(app.descendants(matching: .any)["slot-월-09:00"].waitForExistence(timeout: 5))

        app.buttons["addSlot"].click()
        let error = app.staticTexts["slotError"]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue((error.value as? String ?? error.label).contains("겹칩니다"))
    }
}
