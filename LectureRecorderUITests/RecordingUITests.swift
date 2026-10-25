import XCTest

final class RecordingUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// UI 테스트에서는 시뮬레이션 녹음기를 쓰므로 마이크 없이 흐름만 확인한다.
    @MainActor
    func test녹음을_시작하면_과목과_경과_시간이_보이고_정지하면_저장된다() throws {
        let app = XCUIApplication.launchForTesting()

        let button = app.buttons["recordButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        let elapsed = app.staticTexts["elapsedTime"]
        XCTAssertEqual(text(of: elapsed), "00:00")

        button.click()
        let subject = app.staticTexts["recordingSubject"]
        XCTAssertTrue(subject.waitForExistence(timeout: 5))
        XCTAssertTrue(wait(for: subject, matching: NSPredicate(format: "value == %@", "미분류")))
        // 경과 시간이 흐른다.
        XCTAssertTrue(wait(for: elapsed, matching: NSPredicate(format: "value BEGINSWITH '00:0' AND value != '00:00'"), timeout: 6))

        button.click()
        let saved = app.staticTexts["lastSavedTitle"]
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        XCTAssertTrue(text(of: saved).hasPrefix("저장됨: 미분류"))
        XCTAssertEqual(text(of: elapsed), "00:00")
    }

    /// macOS에서 `Text`의 문구는 label이 아니라 value에 들어 있다.
    @MainActor
    private func text(of element: XCUIElement) -> String {
        (element.value as? String) ?? element.label
    }

    @MainActor
    private func wait(for element: XCUIElement, matching predicate: NSPredicate, timeout: TimeInterval = 5) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}

final class LibraryUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test사이드바에_미분류가_보이고_녹음하면_목록에_나타난다() throws {
        let app = XCUIApplication.launchForTesting()
        XCTAssertTrue(app.staticTexts["미분류"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["emptyRecordingList"].waitForExistence(timeout: 5))

        let button = app.buttons["recordButton"]
        button.click()
        XCTAssertTrue(app.staticTexts["recordingSubject"].waitForExistence(timeout: 5))
        button.click()
        XCTAssertTrue(app.descendants(matching: .any)["recordingList"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["emptyRecordingList"].waitForNonExistence(timeout: 5))
    }
}
