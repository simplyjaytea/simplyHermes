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
        back(app)

        let toolsTab = app.tabBars.buttons["Tools"]
        XCTAssertTrue(toolsTab.waitForExistence(timeout: 10), "The tab bar should show Tools")
        toolsTab.tap()

        openRow(app, "tools.skills", title: "Skills")
        XCTAssertTrue(
            app.staticTexts["Connect to a server first."].waitForExistence(timeout: 5),
            "With no server, the Skills screen should say so"
        )
        back(app)

        openRow(app, "tools.toolsets", title: "Toolsets")
        back(app)

        openRow(app, "tools.plugins", title: "Agent plugins")
        back(app)
    }

    @MainActor
    private func openRow(_ app: XCUIApplication, _ identifier: String, title: String) {
        let row = element(app, identifier)
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Missing Tools row \(identifier)")
        row.tap()
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), "Expected the \(title) screen")
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

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
