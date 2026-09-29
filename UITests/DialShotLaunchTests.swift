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
        let savedRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "history.shot."))
            .firstMatch
        scrollUntilVisible(savedRow, in: app)
        XCTAssertTrue(savedRow.exists)
        XCTAssertFalse(app.descendants(matching: .any)["history.empty"].exists)
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
        let compare = app.buttons["history.compare"]
        scrollUntilVisible(compare, in: app)
        XCTAssertTrue(compare.exists)
        XCTAssertFalse(compare.isEnabled)
    }

    @MainActor
    func testTwoSavedShotsCanBeCompared() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-DialShotResetUITestStore"]
        app.launch()
        recordShot(app, yield: "34")
        recordShot(app, yield: "38")
        app.buttons["history.open"].tap()
        let rowPredicate = NSPredicate(format: "identifier BEGINSWITH %@", "history.shot.")
        let rows = app.buttons.matching(rowPredicate)
        var attempts = 0
        while rows.count < 2 && attempts < 5 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertEqual(rows.count, 2)
        let first = rows.element(boundBy: 0)
        let second = rows.element(boundBy: 1)
        first.tap()
        scrollUntilVisible(second, in: app)
        second.tap()
        let compare = app.buttons["history.compare"]
        scrollUpUntilVisible(compare, in: app)
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
        let empty = app.descendants(matching: .any)["history.empty"]
        scrollUntilVisible(empty, in: app)
        XCTAssertTrue(empty.exists)
    }
}

extension DialShotLaunchTests {
    private func scrollUntilVisible(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 5) {
        var attempts = 0
        while !element.isHittable && attempts < maxSwipes {
            app.swipeUp()
            attempts += 1
        }
    }

    private func scrollUpUntilVisible(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 5) {
        var attempts = 0
        while !element.isHittable && attempts < maxSwipes {
            app.swipeDown()
            attempts += 1
        }
    }
}
