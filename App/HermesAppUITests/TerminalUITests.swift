import XCTest

/// WP-61 CI gate without a server: the Tools tab lists Terminal, and the screen shows its empty state and the
/// New Terminal action. The `echo` run against the WP-03 testbed needs a saved connection first; the live socket
/// is covered by `TerminalLiveTests` in HermesKit.
final class TerminalUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testToolsListsTerminal() {
        let app = XCUIApplication()
        app.launchArguments += ["-HermesOnboarding", "skip", "-HermesLayout", "compact"]
        app.launch()

        openToolsTab(app)
        let row = element(app, labeled: "Terminal")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Tools should list Terminal")
    }

    @MainActor
    func testTerminalScreenOpensWithoutAServer() {
        let app = XCUIApplication()
        app.launchArguments += ["-HermesOnboarding", "skip", "-HermesLayout", "compact"]
        app.launch()

        openToolsTab(app)
        let row = element(app, labeled: "Terminal")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Tools should list Terminal")
        row.tap()
        XCTAssertTrue(app.navigationBars["Terminal"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["New Terminal"].waitForExistence(timeout: 5))
    }

    /// Taps the Tools tab. CI draws the tabs as a vertical rail, and XCUITest found no tab bar to search, so the tab
    /// is found by its label.
    @MainActor
    private func openToolsTab(_ app: XCUIApplication) {
        let tab = element(app, labeled: "Tools")
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "The Tools tab should be on screen")
        tab.tap()
    }

    /// The first on-screen element with this exact label, whatever its type: a List row may be a cell or a button.
    /// A control can also linger in the accessibility tree with no frame, so only a hittable one counts.
    @MainActor
    private func element(_ app: XCUIApplication, labeled label: String) -> XCUIElement {
        let predicate = NSPredicate(format: "label == %@ AND hittable == true", label)
        return app.descendants(matching: .any).matching(predicate).firstMatch
    }
}
