import XCTest

final class DialShotLaunchTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testBootstrapHomeLaunches() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        XCTAssertTrue(app.otherElements["bootstrap.home"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Dial Shot"].exists)
        XCTAssertTrue(app.staticTexts["Timer capture, immutable shot memory, and deterministic next-step guidance land in the next milestones."].exists)
    }
}
