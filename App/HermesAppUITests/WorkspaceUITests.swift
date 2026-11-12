import XCTest

/// WP-37 CI gate: add the testbed gateway, open a server chat and move it to the testbed workspace from the
/// workspace pill. The testbed needs a session for the chat; without one the test is skipped, not passed.
final class WorkspaceUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testWorkspacePickerMovesChatToTestbedWorkspace() throws {
        let url = try XCTUnwrap(
            ProcessInfo.processInfo.environment["HERMES_TESTBED_URL"],
            "Set TEST_RUNNER_HERMES_TESTBED_URL to the testbed dashboard")
        let app = XCUIApplication()
        app.launchArguments += ["-HermesOnboarding", "fresh", "-HermesLayout", "compact"]
        app.launch()

        testbedSignIn(app, url: url)

        let session = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'session.'"))
            .firstMatch
        guard session.waitForExistence(timeout: 15) else {
            throw XCTSkip("The testbed has no session to open")
        }
        session.tap()

        let pill = element(app, "chat.workspace")
        XCTAssertTrue(pill.waitForExistence(timeout: 15), "A server chat should show its workspace pill")
        pill.tap()

        let root = element(app, "workspace./opt/hermes")
        XCTAssertTrue(root.waitForExistence(timeout: 15), "The testbed workspace should be listed")
        root.tap()
        XCTAssertTrue(root.waitForNonExistence(timeout: 15), "A successful move closes the picker")
        XCTAssertTrue(element(app, "chat.workspace").waitForExistence(timeout: 5))
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        testbedElement(app, identifier)
    }
}
