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

        try addTestbedGateway(app, url: url)

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

    /// Same steps as the WP-22 connection test: the welcome screen, the testbed URL, the basic login, then Save.
    @MainActor
    private func addTestbedGateway(_ app: XCUIApplication, url: String) throws {
        let addGateway = element(app, "welcome.addGateway")
        XCTAssertTrue(addGateway.waitForExistence(timeout: 10))
        addGateway.tap()

        let field = element(app, "connection.url")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(url)

        let username = element(app, "connection.username")
        XCTAssertTrue(username.waitForExistence(timeout: 10), "Password sign-in should be picked from the probe")
        username.tap()
        username.typeText("tester")
        let password = element(app, "connection.password")
        password.tap()
        password.typeText("testbed-password")

        let test = element(app, "connection.test")
        if !test.isHittable { app.swipeUp() }
        test.tap()
        XCTAssertTrue(element(app, "connection.testPassed").waitForExistence(timeout: 30))

        element(app, "connection.save").tap()
        XCTAssertTrue(element(app, "welcome.addGateway").waitForNonExistence(timeout: 10))
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
