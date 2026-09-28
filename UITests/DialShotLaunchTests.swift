import XCTest

final class DialShotLaunchTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testTimerCaptureReviewAndSave() throws {
        let app = XCUIApplication()
        app.launch()

        let primary = app.buttons["timer.primary"]
        XCTAssertTrue(primary.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(primary.frame.height, 72)
        primary.tap()

        let firstDrop = app.buttons["timer.firstDrop"]
        XCTAssertTrue(firstDrop.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(firstDrop.frame.height, 72)
        firstDrop.tap()

        XCTAssertEqual(primary.label, "Stop shot")
        primary.tap()

        let yield = app.textFields["capture.yield"]
        XCTAssertTrue(yield.waitForExistence(timeout: 5))
        yield.tap()
        yield.typeText("34")
        app.buttons["Done"].tap()
        app.swipeUp()

        let sour = app.buttons["note.sour"]
        XCTAssertGreaterThanOrEqual(sour.frame.height, 44)
        sour.tap()
        app.buttons["flow.fast"].tap()
        app.buttons["capture.review"].tap()

        XCTAssertTrue(app.staticTexts["Review before saving"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["review.suggestion"].label.contains("Grind finer"))
        app.buttons["review.save"].tap()
        XCTAssertTrue(app.staticTexts["Shot saved on this iPhone."].waitForExistence(timeout: 5))
    }

    @MainActor
    func testAccessibilityTextSizeKeepsPrimaryControlLarge() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"]
        app.launch()
        let primary = app.buttons["timer.primary"]
        XCTAssertTrue(primary.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(primary.frame.height, 72)
    }
}
