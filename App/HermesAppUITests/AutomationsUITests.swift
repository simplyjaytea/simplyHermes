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
        // Launch opens the newest chat, which pushes over the tab bar. Back out to reach the tabs.
        XCTAssertTrue(app.navigationBars["Backup cron fix"].waitForExistence(timeout: 10))
        back(app)
        let tab = app.tabBars.buttons["Automations"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "The tab bar should show Automations")
        tab.tap()
        XCTAssertTrue(app.navigationBars["Automations"].waitForExistence(timeout: 10))
    }

    /// Backs out of the screen the test pushed. Taps the back button when the runner exposes it.
    /// Otherwise the interactive back swipe pops the screen, so the tab bar returns either way.
    @MainActor
    private func back(_ app: XCUIApplication) {
        let button = app.navigationBars.buttons.element(boundBy: 0)
        if button.waitForExistence(timeout: 2) {
            button.tap()
            return
        }
        add(XCTAttachment(string: app.debugDescription))
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end)
    }
}
