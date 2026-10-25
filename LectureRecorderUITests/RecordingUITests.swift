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
        XCTAssertEqual(app.staticTexts["elapsedTime"].label, "00:00")

        button.click()
        let subject = app.staticTexts["recordingSubject"]
        XCTAssertTrue(subject.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForLabel(of: subject, toBe: "미분류"))
        // 경과 시간이 흐른다.
        XCTAssertTrue(wait(for: app.staticTexts["elapsedTime"], matching: NSPredicate(format: "label BEGINSWITH '00:0' AND label != '00:00'"), timeout: 6))

        button.click()
        let saved = app.staticTexts["lastSavedTitle"]
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        XCTAssertTrue(saved.label.hasPrefix("저장됨: 미분류"))
        XCTAssertEqual(app.staticTexts["elapsedTime"].label, "00:00")
    }

    private func waitForLabel(of element: XCUIElement, toBe expected: String, timeout: TimeInterval = 5) -> Bool {
        wait(for: element, matching: NSPredicate(format: "label == %@", expected), timeout: timeout)
    }

    private func wait(for element: XCUIElement, matching predicate: NSPredicate, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
