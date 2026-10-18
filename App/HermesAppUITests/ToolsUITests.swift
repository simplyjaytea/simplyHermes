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

        let toolsTab = app.tabBars.buttons["Tools"]
        XCTAssertTrue(toolsTab.waitForExistence(timeout: 10))
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

    @MainActor
    private func back(_ app: XCUIApplication) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
