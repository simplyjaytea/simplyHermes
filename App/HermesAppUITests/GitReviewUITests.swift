import XCTest

/// Git review entry (parity gap #4): a server chat with a workspace folder shows "Review changes" in its header, and it
/// opens the Git review of that folder. The testbed's /opt/hermes is a git checkout, so the review loads there. The
/// testbed needs a session for the chat; without one the test is skipped, not passed.
final class GitReviewUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testReviewChangesOpensTheChatFoldersGitReview() throws {
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

        // Put the chat in the testbed's git checkout, as WorkspaceUITests does.
        let pill = element(app, "chat.workspace")
        XCTAssertTrue(pill.waitForExistence(timeout: 15), "A server chat should show its workspace pill")
        pill.tap()
        let root = element(app, "workspace./opt/hermes")
        XCTAssertTrue(root.waitForExistence(timeout: 15), "The testbed workspace should be listed")
        root.tap()
        XCTAssertTrue(root.waitForNonExistence(timeout: 15), "A successful move closes the picker")

        let review = element(app, "chat.gitReview")
        XCTAssertTrue(review.waitForExistence(timeout: 10), "A chat with a folder offers Review changes")
        review.tap()
        XCTAssertTrue(app.navigationBars["Git review"].waitForExistence(timeout: 10), "The Git review opens")
        XCTAssertTrue(app.segmentedControls.buttons["Uncommitted"].exists, "It shows the scope picker")
        XCTAssertFalse(
            element(app, "gitReview.error").waitForExistence(timeout: 10), "The review of /opt/hermes loads")

        element(app, "gitReview.done").tap()
        XCTAssertTrue(app.navigationBars["Git review"].waitForNonExistence(timeout: 5), "Done closes it")
        XCTAssertTrue(element(app, "chat.gitReview").exists, "Back in the chat")
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

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
