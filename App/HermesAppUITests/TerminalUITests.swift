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

        app.tabBars.buttons["Tools"].tap()
        let row = app.buttons["Terminal"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Tools should list Terminal")
    }

    @MainActor
    func testTerminalScreenOpensWithoutAServer() {
        let app = XCUIApplication()
        app.launchArguments += ["-HermesOnboarding", "skip", "-HermesLayout", "compact"]
        app.launch()

        app.tabBars.buttons["Tools"].tap()
        app.buttons["Terminal"].tap()
        XCTAssertTrue(app.navigationBars["Terminal"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["New Terminal"].waitForExistence(timeout: 5))
    }
}
