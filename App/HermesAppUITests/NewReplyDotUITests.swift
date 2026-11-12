import XCTest

/// Row 74 (review m3 on #141): a reply that streams in while the user is scrolled up lights the dot on the
/// scroll-to-latest button, and Scroll to latest clears it. Uses the testbed's `long_stream` scenario (3,000 chunks).
final class NewReplyDotUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testAReplyWhileScrolledUpShowsTheDot() throws {
        let url = try XCTUnwrap(
            ProcessInfo.processInfo.environment["HERMES_TESTBED_URL"],
            "Set TEST_RUNNER_HERMES_TESTBED_URL to the testbed dashboard")
        let app = XCUIApplication()
        app.launchArguments += ["-HermesOnboarding", "fresh", "-HermesLayout", "compact"]
        app.launch()
        testbedSignIn(app, url: url)
        testbedWaitUntilConnected(app)
        testbedOpenAChat(app)

        let field = testbedElement(app, "composer.field")
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("[[scenario:long_stream]] stream please")
        testbedElement(app, "composer.send").tap()
        let transcript = testbedElement(app, "transcript")
        XCTAssertTrue(transcript.waitForExistence(timeout: 10))
        // Scroll up while the reply is still streaming in.
        transcript.swipeDown()
        transcript.swipeDown()

        let dot = testbedElement(app, "chat.newReplyDot")
        XCTAssertTrue(dot.waitForExistence(timeout: 20), "New text while scrolled up lights the dot")
        testbedElement(app, "chat.scrollToBottom").tap()
        XCTAssertTrue(dot.waitForNonExistence(timeout: 10), "Back at the latest, the dot goes")
    }
}
