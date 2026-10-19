import XCTest

/// WP-61 CI gate without a server: the Tools section lists Terminal, and the screen shows its empty state and the
/// New Terminal action. The `echo` run against the WP-03 testbed needs a saved connection first; the live socket
/// is covered by `TerminalLiveTests` in HermesKit.
final class TerminalUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testToolsListsTerminal() {
        let app = launchOnTools()

        XCTAssertTrue(element(app, labeled: "Terminal").waitForExistence(timeout: 10), "Tools should list Terminal")
    }

    @MainActor
    func testTerminalScreenOpensWithoutAServer() {
        let app = launchOnTools()

        let row = element(app, labeled: "Terminal")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Tools should list Terminal")
        row.tap()
        XCTAssertTrue(app.navigationBars["Terminal"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["New Terminal"].waitForExistence(timeout: 5))
    }

    /// Launches with the Tools section selected. CI draws the compact tabs as a vertical rail that XCUITest does not
    /// find as a tab bar, so the section opens from a launch option instead of a tab tap.
    @MainActor
    private func launchOnTools() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-HermesOnboarding", "skip", "-HermesLayout", "compact", "-HermesSection", "tools"]
        app.launch()
        return app
    }

    /// The first on-screen element with this exact label, whatever its type: a List row may be a cell or a button.
    /// A control can also linger in the accessibility tree with no frame, so only an element with a size counts.
    @MainActor
    private func element(_ app: XCUIApplication, labeled label: String) -> XCUIElement {
        let matches = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label))
        let sized = matches.allElementsBoundByIndex.first { $0.frame.width > 0 && $0.frame.height > 0 }
        return sized ?? matches.firstMatch
    }
}
