import XCTest

final class AutomationsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testAutomationsTabOpensItsList() {
        let app = XCUIApplication()
        app.launchArguments += ["-HermesOnboarding", "skip"]
        app.launchArguments += ["-HermesLayout", "compact"]
        app.launch()
        let tab = app.tabBars.buttons["Automations"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        tab.tap()
        XCTAssertTrue(app.navigationBars["Automations"].waitForExistence(timeout: 10))
    }
}
