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
        let transcript = testbedElement(app, "transcript")
        let toLatest = testbedElement(app, "chat.scrollToBottom")
        let dot = testbedElement(app, "chat.newReplyDot")
        // What the screen held, for the message of a failed check.
        func seen() -> String {
            let keyboard = app.keyboards.firstMatch
            return "toLatest=\(toLatest.exists ? toLatest.label : "absent") frame=\(toLatest.frame) "
                + "dot=\(dot.exists) keyboard=\(keyboard.exists ? "\(keyboard.frame)" : "none") "
                + "transcript=\(transcript.frame) field=\(field.value as? String ?? "nil")"
        }

        // The stream lasts about ten seconds. On a slow runner the scroll up can take effect only after it ended, and
        // then no new text arrives to light the dot (run 43649410739), so a second stream gets a second chance.
        for attempt in 1...2 where !dot.exists {
            if toLatest.exists { toLatest.tap() }
            field.tap()
            field.typeText("[[scenario:long_stream]] stream please \(attempt)")
            testbedElement(app, "composer.send").tap()
            XCTAssertTrue(transcript.waitForExistence(timeout: 10))
            // With the keyboard up the small screen leaves the transcript a strip. Drag from it down over the keyboard:
            // the transcript dismisses the keyboard interactively.
            if app.keyboards.firstMatch.exists {
                transcript.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                    .press(
                        forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
                    )
            }
            // Scroll up while the reply is still streaming in. The first swipes can land before the transcript is tall
            // enough to scroll, and the chat then keeps following. The scroll-to-latest button shows only once the
            // chat has stopped following, so swipe until it is there.
            for _ in 0..<8 where !toLatest.exists {
                transcript.swipeDown()
                _ = toLatest.waitForExistence(timeout: 1)
            }
            XCTAssertTrue(
                toLatest.exists, "Swiping down should scroll the transcript up and show Scroll to latest. \(seen())")
            _ = dot.waitForExistence(timeout: 15)
        }
        XCTAssertTrue(dot.waitForExistence(timeout: 20), "New text while scrolled up lights the dot. \(seen())")
        toLatest.tap()
        XCTAssertTrue(dot.waitForNonExistence(timeout: 10), "Back at the latest, the dot goes. \(seen())")
    }
}
