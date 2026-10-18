import XCTest

final class ToolsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// WP-51: the Tools tab opens Skills, Toolsets and Agent plugins. With no server connected, Skills says so.
    @MainActor
    func testToolsTabOpensSkillsToolsetsAndPlugins() {
        let app = XCUIApplication()
        app.launchArguments += ["-HermesOnboarding", "skip"]
        app.launchArguments += ["-HermesLayout", "compact"]
        app.launch()

        // Launch opens the newest chat, which pushes over the tab bar. Back out to reach the tabs.
        XCTAssertTrue(app.navigationBars["Backup cron fix"].waitForExistence(timeout: 10))
        back(app, from: "Backup cron fix", to: "Chats")

        let toolsTab = app.tabBars.buttons["Tools"]
        XCTAssertTrue(toolsTab.waitForExistence(timeout: 10), "The tab bar should show Tools")
        toolsTab.tap()

        openRow(app, "tools.skills", title: "Skills")
        XCTAssertTrue(
            app.staticTexts["Connect to a server first."].waitForExistence(timeout: 5),
            "With no server, the Skills screen should say so"
        )
        back(app, from: "Skills", to: "Tools")

        openRow(app, "tools.toolsets", title: "Toolsets")
        back(app, from: "Toolsets", to: "Tools")

        openRow(app, "tools.plugins", title: "Agent plugins")
        back(app, from: "Agent plugins", to: "Tools")
    }

    @MainActor
    private func openRow(_ app: XCUIApplication, _ identifier: String, title: String) {
        let row = element(app, identifier)
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Missing Tools row \(identifier)")
        row.tap()
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), "Expected the \(title) screen")
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

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
