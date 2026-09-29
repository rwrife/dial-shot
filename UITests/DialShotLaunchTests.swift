import XCTest

final class DialShotLaunchTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testTimerCaptureReviewAndSave() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-DialShotResetUITestStore"]
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
        app.buttons["history.open"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["history.empty"].exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "history.shot.")).firstMatch.exists)
    }

    @MainActor
    func testAccessibilityTextSizeKeepsPrimaryControlLarge() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-DialShotResetUITestStore", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"]
        app.launch()
        let primary = app.buttons["timer.primary"]
        XCTAssertTrue(primary.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(primary.frame.height, 72)
    }
}

extension DialShotLaunchTests {
    @MainActor
    func testBeanHistoryShowsSavedShotAndComparisonSelection() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-DialShotResetUITestStore"]
        app.launch()
        XCTAssertTrue(app.buttons["history.open"].waitForExistence(timeout: 10))
        app.buttons["history.open"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["bean.activeRecipe"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["history.trend"].exists)
        XCTAssertTrue(app.textFields["history.beanSearch"].exists)
        XCTAssertTrue(app.textFields["history.grinderSearch"].exists)
        XCTAssertTrue(app.buttons["history.verdict"].exists)
        XCTAssertTrue(app.buttons["history.compare"].exists)
        XCTAssertFalse(app.buttons["history.compare"].isEnabled)
    }

    @MainActor
    func testTwoSavedShotsCanBeCompared() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-DialShotResetUITestStore"]
        app.launch()
        recordShot(app, yield: "34")
        recordShot(app, yield: "38")
        app.buttons["history.open"].tap()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "history.shot."))
        XCTAssertEqual(rows.count, 2)
        rows.element(boundBy: 0).tap()
        rows.element(boundBy: 1).tap()
        let compare = app.buttons["history.compare"]
        XCTAssertTrue(compare.isEnabled)
        compare.tap()
        XCTAssertTrue(app.descendants(matching: .any)["comparison.view"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Different")).firstMatch.exists)
    }

    @MainActor
    private func recordShot(_ app: XCUIApplication, yield: String) {
        let primary = app.buttons["timer.primary"]
        XCTAssertTrue(primary.waitForExistence(timeout: 5))
        primary.tap()
        primary.tap()
        let field = app.textFields["capture.yield"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(yield)
        app.buttons["Done"].tap()
        app.swipeUp()
        app.buttons["capture.review"].tap()
        app.buttons["review.save"].tap()
        XCTAssertTrue(app.staticTexts["Shot saved on this iPhone."].waitForExistence(timeout: 5))
    }

    @MainActor
    func testHistorySupportsAccessibilityTextSize() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-DialShotResetUITestStore", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"]
        app.launch()
        app.buttons["history.open"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["bean.activeRecipe"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["history.empty"].exists)
    }
}
