import XCTest

/// WP-7 AT-2b: a local chat works with no server configured. Three messages get three replies from the injected fake,
/// the network trap records no request, and the messages are still there after a relaunch.
///
/// The fake answers with `Reply from Test-Model-X` and names itself, so the replies can be told apart from a server's.
/// Written to compile in the App UI test target; it runs in the App CI job on the Simulator.
final class LocalChatUITests: XCTestCase {
    private let fakeName = "Test-Model-X"
    private let messages = ["Question one", "Question two", "Question three"]

    override func setUp() {
        continueAfterFailure = false
    }

    /// Positive control: the trap must see a real connection, or its zero below proves nothing.
    @MainActor
    func testNetworkTrapCountsARealConnection() {
        let app = XCUIApplication()
        app.launchArguments += ["-HermesOnboarding", "skip", "-uiTestNetworkTrap", "-uiTestNetworkProbe"]
        app.launch()

        let readout = element(app, "uiTest.networkRequests")
        XCTAssertTrue(readout.waitForExistence(timeout: 15), "The trap readout should be in the shell")
        let counted = NSPredicate(format: "label != '0'")
        let wait = XCTNSPredicateExpectation(predicate: counted, object: readout)
        XCTAssertEqual(XCTWaiter().wait(for: [wait], timeout: 15), .completed, "The probe connection should be counted")
        app.terminate()
    }

    @MainActor
    func testLocalChatWithNoServerAnswersOnDeviceAndKeepsItsMessages() {
        // `skip` keeps the saved chat list on disk, so the relaunch below can find the chat again.
        let arguments = [
            "-HermesOnboarding", "skip",
            "-chatModeDefault", "local",
            "-uiTestNetworkTrap",
            "-uiTestLocalExecutor=\(fakeName)",
        ]
        let app = XCUIApplication()
        app.launchArguments += arguments
        app.launch()

        // The toolbar button carries the identifier. A label lookup would also match the hidden keyboard-shortcut button.
        let newChat = app.buttons.matching(identifier: "shell.newChat").firstMatch
        XCTAssertTrue(newChat.waitForExistence(timeout: 15), "New chat should be in the shell")
        XCTAssertTrue(newChat.isHittable, "New chat should be on screen")
        newChat.tap()

        for (index, text) in messages.enumerated() {
            let field = element(app, "composer.field")
            XCTAssertTrue(field.waitForExistence(timeout: 10))
            field.tap()
            field.typeText(text)
            element(app, "composer.send").tap()

            XCTAssertTrue(
                app.staticTexts.matching(identifier: "local.message.model").element(boundBy: index)
                    .waitForExistence(timeout: 20),
                "Reply \(index + 1) should appear")
        }

        let labels = app.staticTexts.matching(identifier: "local.message.model")
        XCTAssertEqual(labels.count, messages.count)
        XCTAssertEqual(labels.firstMatch.label, "On this iPhone · \(fakeName)")
        XCTAssertEqual(element(app, "uiTest.networkRequests").label, "0", "A local chat must make no request")

        app.terminate()
        app.launch()

        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'session.local-'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "The local chat should still be listed")
        row.tap()
        for text in messages {
            XCTAssertTrue(app.staticTexts[text].waitForExistence(timeout: 10), "\(text) should survive a relaunch")
        }
        XCTAssertEqual(element(app, "uiTest.networkRequests").label, "0")
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
