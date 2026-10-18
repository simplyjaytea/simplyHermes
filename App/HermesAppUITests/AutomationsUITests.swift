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
        back(app, from: "Backup cron fix", to: "Chats")
        let tab = app.tabBars.buttons["Automations"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "The tab bar should show Automations")
        tab.tap()
        XCTAssertTrue(app.navigationBars["Automations"].waitForExistence(timeout: 10))
    }

    /// Pops `current` back to `previous`. The runner does not reliably expose the back button, so the
    /// leading edge of the bar, where the button sits, is tapped. The back swipe is the fallback.
    @MainActor
    private func back(_ app: XCUIApplication, from current: String, to previous: String) {
        app.navigationBars[current].coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.25)).tap()
        if !app.navigationBars[previous].waitForExistence(timeout: 3) {
            add(XCTAttachment(string: app.debugDescription))
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        XCTAssertTrue(
            app.navigationBars[previous].waitForExistence(timeout: 5),
            "Expected the \(previous) screen after backing out of \(current)"
        )
    }
}
