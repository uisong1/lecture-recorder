import XCTest

/// 녹음 → 목록 흐름의 UI 테스트. 시뮬레이션 녹음기와 임시 폴더를 쓰며, 휴지통은 앱이 임시 폴더로 대신한다.
final class LibraryFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 녹음을 시작해 `afterStart`를 하고 정지한다. 짧은 녹음 확인 창은 저장을 고른다.
    @MainActor
    private func record(in app: XCUIApplication, afterStart: () -> Void = {}) {
        let button = app.buttons["recordButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.click()
        XCTAssertTrue(app.staticTexts["recordingSubject"].waitForExistence(timeout: 5))
        afterStart()
        button.click()
        app.keepShortRecordingIfAsked()
        XCTAssertTrue(app.staticTexts["lastSavedTitle"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func openSidebar(_ identifier: String, in app: XCUIApplication) {
        let item = app.descendants(matching: .any)[identifier].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.click()
    }

    @MainActor
    private func text(of element: XCUIElement) -> String {
        (element.value as? String) ?? element.label
    }

    @MainActor
    func test녹음_중_북마크를_추가하고_정지하면_목록_행에_북마크_1이_보인다() throws {
        let app = XCUIApplication.launchForTesting()

        record(in: app) {
            let bookmark = app.buttons["bookmarkButton"]
            XCTAssertTrue(bookmark.waitForExistence(timeout: 5))
            bookmark.click()
        }
        openSidebar("sidebar-unclassified", in: app)

        let status = app.staticTexts["recordingStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(text(of: status).contains("북마크 1"))
    }

    @MainActor
    func test녹음을_휴지통으로_이동하면_목록에서_사라진다() throws {
        let app = XCUIApplication.launchForTesting()
        record(in: app)
        openSidebar("sidebar-unclassified", in: app)

        let row = app.staticTexts["recordingRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.rightClick()
        let trash = app.menuItems["휴지통으로 이동…"]
        XCTAssertTrue(trash.waitForExistence(timeout: 5))
        trash.click()
        // 확인 창의 버튼 (메뉴 항목이 아니라 버튼).
        let confirm = app.buttons.matching(NSPredicate(format: "label == %@", "휴지통으로 이동")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.click()

        XCTAssertTrue(row.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["emptyRecordings"].waitForExistence(timeout: 5))
    }

    @MainActor
    func test설정에서_녹음_폴더_다시_읽기를_누르면_결과_문구가_보인다() throws {
        let app = XCUIApplication.launchForTesting()
        app.openSettings(tab: "녹음 파일")

        let button = app.buttons["rescanButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.click()

        let message = app.staticTexts["rescanMessage"]
        XCTAssertTrue(message.waitForExistence(timeout: 10))
        XCTAssertFalse(text(of: message).isEmpty)
    }

    @MainActor
    func test모든_녹음은_과목이_섞인_목록을_보인다() throws {
        let app = XCUIApplication.launchForTesting()
        // 과목을 하나 만들고 설정 창을 닫는다.
        app.openSettings(tab: "과목")
        let nameField = app.textFields["newSubjectName"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.click()
        nameField.typeText("자료구조\r")
        XCTAssertTrue(app.textFields["subjectName-자료구조"].waitForExistence(timeout: 5))
        app.typeKey("w", modifierFlags: .command)

        // 하나는 미분류로 두고, 다른 하나는 저장 직후 과목을 자료구조로 바꾼다.
        record(in: app)
        record(in: app)
        app.buttons["editLastSaved"].click()
        let subjectMenu = app.descendants(matching: .any)["lastSavedSubjectMenu"].firstMatch
        XCTAssertTrue(subjectMenu.waitForExistence(timeout: 5))
        subjectMenu.click()
        app.menuItems["자료구조"].click()

        // 모든 녹음에는 두 과목의 녹음이 섞여 있고, 과목별로 보면 각각 하나씩이다.
        openSidebar("sidebar-all", in: app)
        XCTAssertTrue(app.staticTexts["recordingRow"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(identifier: "recordingRow").count, 2)

        openSidebar("sidebar-subject-자료구조", in: app)
        XCTAssertTrue(app.staticTexts["recordingRow"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(identifier: "recordingRow").count, 1)

        openSidebar("sidebar-unclassified", in: app)
        XCTAssertTrue(app.staticTexts["recordingRow"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(identifier: "recordingRow").count, 1)

        openSidebar("sidebar-all", in: app)
        XCTAssertTrue(app.staticTexts["recordingRow"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(identifier: "recordingRow").count, 2)
    }
}
