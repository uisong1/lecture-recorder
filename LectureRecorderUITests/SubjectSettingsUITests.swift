import XCTest

final class SubjectSettingsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test과목을_추가하고_이름을_바꾸고_삭제한다() throws {
        let app = XCUIApplication.launchForTesting()
        app.openSettings(tab: "과목")

        let nameField = app.textFields["newSubjectName"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.click()
        nameField.typeText("자료구조\r")
        XCTAssertTrue(app.textFields["subjectName-자료구조"].waitForExistence(timeout: 5))

        // 같은 이름은 거부된다.
        nameField.click()
        nameField.typeText("자료구조\r")
        XCTAssertTrue(app.staticTexts["subjectError"].waitForExistence(timeout: 5))

        let row = app.textFields["subjectName-자료구조"]
        row.click()
        row.typeKey("a", modifierFlags: .command)
        row.typeText("자료구조론\r")
        XCTAssertTrue(app.textFields["subjectName-자료구조론"].waitForExistence(timeout: 5))

        app.buttons["deleteSubject-자료구조론"].click()
        XCTAssertTrue(app.textFields["subjectName-자료구조론"].waitForNonExistence(timeout: 5))
    }
}
