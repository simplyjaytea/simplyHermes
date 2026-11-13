import XCTest

/// Git review entry (parity gap #4): a server chat with a workspace folder shows "Review changes" in its header, and it
/// opens the Git review of that folder. The testbed's /opt/hermes is a git checkout, so the review loads there. With no
/// chat on the testbed, the test makes one; it never skips.
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
        testbedSignIn(app, url: url)
        testbedWaitUntilConnected(app)
        // Opens a listed chat, or makes one, so the test never skips in CI (review m1 on #129).
        testbedOpenAChat(app)

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

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        testbedElement(app, identifier)
    }
}
