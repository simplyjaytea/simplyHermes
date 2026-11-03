import XCTest

/// WP-8 AT-1b and AT-3b: an online chat while the gateway is stopped.
///
/// The test adds the testbed dashboard through the wizard, as `ConnectionSetupUITests` does, and then stops and starts
/// it with the DEBUG switch `-uiTestGatewayToggle` (`uiTest.gatewayToggle`). The switch makes new connections refuse and
/// sets the network path to none. It does not stop the Docker container: the CI job cannot be reached from a UI test.
/// Needs `HERMES_TESTBED_URL` (passed as `TEST_RUNNER_HERMES_TESTBED_URL`); without it the tests fail rather than skip.
final class StatusPillUITests: XCTestCase {
    private let draft = "ping"

    override func setUp() {
        continueAfterFailure = false
    }

    /// AT-1b: with the gateway stopped, a sent message waits as "Waiting to send", the pill says "Can't reach", and
    /// nothing answers for 10 seconds, locally or from the server. Starting the gateway delivers the message once.
    @MainActor
    func testMessageWaitsWhileTheGatewayIsStoppedAndSendsOnceWhenItIsBack() throws {
        let app = try launchWithTestbed()
        openLiveServerChat(app)
        let repliesBefore = replyRowCount(app)

        toggleGateway(app, expecting: "Start gateway")
        typeAndSend(app, draft)

        if !app.staticTexts["Waiting to send"].waitForExistence(timeout: 10) {
            failWithOutageState(app, "The message should wait")
        }
        let pill = element(app, "chat.pill")
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        XCTAssertTrue(pill.label.contains("Can't reach"), "The pill should say Can't reach, not \(pill.label)")
        XCTAssertTrue(element(app, "chat.outageBanner").waitForExistence(timeout: 5))

        // An inverted expectation passes only if nothing fulfils it in the 10 seconds.
        let quiet = XCTestExpectation(description: "No reply in 10 seconds")
        quiet.isInverted = true
        wait(for: [quiet], timeout: 10)
        XCTAssertEqual(replyRowCount(app), repliesBefore, "No assistant row should appear while the gateway is stopped")
        XCTAssertEqual(element(app, "uiTest.localReplies").label, "0", "The on-device model must not answer")

        toggleGateway(app, expecting: "Stop gateway")
        XCTAssertTrue(
            app.staticTexts["Waiting to send"].waitForNonExistence(timeout: 30),
            "The waiting message should send once the gateway is back")
        // A delivered message leaves the waiting row and appears once in the transcript, not twice.
        XCTAssertEqual(
            app.staticTexts.matching(NSPredicate(format: "label == %@", draft)).count, 1,
            "The message should be delivered exactly once")
        XCTAssertEqual(element(app, "uiTest.localReplies").label, "0")
    }

    /// AT-3b: with the gateway stopped, every banner action leaves this chat without an assistant row, and
    /// "Continue in a new Local chat" opens a different chat that carries the draft.
    @MainActor
    func testEveryBannerActionKeepsThisChatSilentAndContinueCarriesTheDraft() throws {
        let app = try launchWithTestbed()
        openLiveServerChat(app)
        toggleGateway(app, expecting: "Start gateway")

        let field = element(app, "composer.field")
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(draft)
        let repliesBefore = replyRowCount(app)

        let banner = element(app, "chat.outageBanner")
        if !banner.waitForExistence(timeout: 10) {
            failWithOutageState(app, "The outage banner should show while the gateway is stopped")
        }

        let tryAgain = element(app, "outage.tryAgain")
        XCTAssertTrue(tryAgain.waitForExistence(timeout: 5))
        tryAgain.tap()
        XCTAssertTrue(
            banner.waitForExistence(timeout: 10), "Try again should keep the banner while the gateway is stopped")
        XCTAssertEqual(replyRowCount(app), repliesBefore, "Try again must not produce an assistant row")

        let continueLocal = element(app, "outage.continueLocal")
        XCTAssertTrue(continueLocal.waitForExistence(timeout: 5))
        XCTAssertEqual(continueLocal.label, "Continue in a new Local chat")
        continueLocal.tap()

        let local = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'session.local-'")).firstMatch
        XCTAssertTrue(local.waitForExistence(timeout: 10), "A new Local chat should open")
        let carried = element(app, "composer.field")
        XCTAssertTrue(carried.waitForExistence(timeout: 10))
        XCTAssertEqual(carried.value as? String, draft, "The new Local chat should carry the draft")
        XCTAssertEqual(element(app, "uiTest.localReplies").label, "0", "Nothing answers until the user sends")
    }

    /// Gilfoyle M1: a message that waited while its chat could not reach the server is sent once when the server is back,
    /// even when that chat is not on screen then. The first chat is found as the second row, because a new chat is listed
    /// first.
    @MainActor
    func testWaitingMessageSendsOnceWhenItsChatComesBackOffScreen() throws {
        let app = try launchWithTestbed()
        openLiveServerChat(app)
        toggleGateway(app, expecting: "Start gateway")
        typeAndSend(app, draft)
        if !app.staticTexts["Waiting to send"].waitForExistence(timeout: 10) {
            failWithOutageState(app, "The message should wait")
        }

        // Another chat takes the screen while the gateway is down.
        app.buttons.matching(identifier: "shell.newChat").firstMatch.tap()
        XCTAssertTrue(element(app, "composer.field").waitForExistence(timeout: 10))

        toggleGateway(app, expecting: "Stop gateway")

        let firstChat = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'session.'")).element(boundBy: 1)
        XCTAssertTrue(firstChat.waitForExistence(timeout: 10), "The first chat should be listed")
        firstChat.tap()

        XCTAssertTrue(
            app.staticTexts["Waiting to send"].waitForNonExistence(timeout: 30),
            "The waiting message should send once the chat is back")
        XCTAssertEqual(
            app.staticTexts.matching(NSPredicate(format: "label == %@", draft)).count, 1,
            "The message should be delivered exactly once")
    }

    // MARK: Helpers

    /// Records the accessibility tree, the screen and the visible text when a chat fails to become live (WP-8).
    @MainActor
    private func failWithChatState(_ app: XCUIApplication, _ message: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "chat-state"
        shot.lifetime = .keepAlways
        add(shot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "accessibility-tree"
        tree.lifetime = .keepAlways
        add(tree)
        let visible = app.staticTexts.allElementsBoundByIndex.prefix(40).map(\.label).joined(separator: " | ")
        XCTFail("\(message) [visible=\(visible)]")
    }

    /// Records what the screen shows when an outage assertion fails: the pill, the banner, the switch and the waiting row.
    /// The screenshot is kept in the result bundle, so a failed run shows the state the chat was in.
    @MainActor
    private func failWithOutageState(_ app: XCUIApplication, _ message: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "outage-state"
        shot.lifetime = .keepAlways
        add(shot)
        let pill = element(app, "chat.pill")
        let state = [
            "pill=\(pill.exists ? pill.label : "absent")",
            "banner=\(element(app, "chat.outageBanner").exists)",
            "switch=\(element(app, "uiTest.gatewayToggle").label)",
            "waiting=\(app.staticTexts["Waiting to send"].exists)",
            "summary=\(element(app, "uiTest.chatStatus").label)",
        ].joined(separator: " ")
        // continueAfterFailure is false (setUp), so the test stops here.
        XCTFail("\(message) [\(state)]")
    }

    /// Launches the app, adds the testbed through the wizard, and returns the app on the shell with the switch on screen.
    @MainActor
    private func launchWithTestbed() throws -> XCUIApplication {
        let url = try XCTUnwrap(
            ProcessInfo.processInfo.environment["HERMES_TESTBED_URL"],
            "Set TEST_RUNNER_HERMES_TESTBED_URL to the testbed dashboard")
        let app = XCUIApplication()
        app.launchArguments += [
            "-HermesOnboarding", "fresh", "-HermesLayout", "compact",
            "-chatModeDefault", "online",
            "-uiTestGatewayToggle", "-uiTestLocalExecutor=Test-Model-X",
        ]
        app.launch()

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
        XCTAssertTrue(element(app, "connection.testPassed").waitForExistence(timeout: 30), "The testbed should pass")

        element(app, "connection.save").tap()
        XCTAssertTrue(element(app, "welcome.addGateway").waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.buttons.matching(identifier: "shell.newChat").firstMatch.waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    private func openNewOnlineChat(_ app: XCUIApplication) {
        let newChat = app.buttons.matching(identifier: "shell.newChat").firstMatch
        XCTAssertTrue(newChat.waitForExistence(timeout: 15), "New chat should be in the shell")
        newChat.tap()
        XCTAssertTrue(element(app, "composer.field").waitForExistence(timeout: 10), "The composer should open")
    }

    /// A live server chat whose first turn is done, while the gateway is up. The outage tests need one: a new chat is a
    /// placeholder until its first message, and a placeholder has no status bar, banner or outbox (WP-8).
    @MainActor
    private func openLiveServerChat(_ app: XCUIApplication) {
        // The wizard saves the server without connecting it, and a new chat needs a connected server (WP-8).
        connectSavedServer(app)
        openNewOnlineChat(app)
        typeAndSend(app, "hello")
        // While the server connects, the first send is refused with a "still connecting" note and the text stays in the
        // composer. Send again, while the send button is enabled, until the chat is live.
        let pill = element(app, "chat.pill")
        var attempts = 1
        while !pill.waitForExistence(timeout: 10), attempts < 6 {
            let send = element(app, "composer.send")
            if send.exists, send.isEnabled { send.tap() }
            attempts += 1
        }
        // Positive check before any outage: the pill is its own element, and the chat is connected.
        if !pill.exists {
            failWithChatState(app, "The status pill should be an element of its own after \(attempts) sends")
        }
        XCTAssertTrue(
            pill.label.hasPrefix("Online chat."), "Before the outage the chat should be connected: \(pill.label)")
        // The user's message and the testbed's reply are both message rows, so the second one means the turn is done.
        let reply = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'message.'")).element(boundBy: 1)
        XCTAssertTrue(reply.waitForExistence(timeout: 60), "The testbed should answer the first message")
    }

    /// Connects the saved server the way a user does: Settings, the server, then Connect in its menu. It is a no-op when
    /// the server is already connected, because the menu then offers Disconnect instead (WP-8).
    @MainActor
    private func connectSavedServer(_ app: XCUIApplication) {
        tabButton(app, "Settings").tap()
        let servers = element(app, "settings.servers")
        XCTAssertTrue(servers.waitForExistence(timeout: 10), "Settings should list the servers")
        servers.tap()
        let server = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'server.'")).firstMatch
        XCTAssertTrue(server.waitForExistence(timeout: 10), "The saved server should be listed")
        server.press(forDuration: 1.0)
        let connect = app.buttons["Connect"]
        if connect.waitForExistence(timeout: 5) { connect.tap() }
        tabButton(app, "Chats").tap()
    }

    /// The bottom tab with this name. A tab bar button is preferred, so the other buttons of the same name don't match.
    @MainActor
    private func tabButton(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        let inBar = app.tabBars.buttons[name]
        return inBar.exists ? inBar : app.buttons[name].firstMatch
    }

    /// Taps the switch and checks the label it shows afterwards, which is the next action.
    @MainActor
    private func toggleGateway(_ app: XCUIApplication, expecting label: String) {
        let toggle = element(app, "uiTest.gatewayToggle")
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()
        let relabelled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", label), object: toggle)
        if XCTWaiter().wait(for: [relabelled], timeout: 5) != .completed {
            // Record what the tap saw, so a failed run says whether the tap missed or the label did not change.
            add(XCTAttachment(screenshot: app.screenshot()))
            XCTFail(
                "The switch should now read \(label), not \(toggle.label). "
                    + "frame=\(toggle.frame) hittable=\(toggle.isHittable) exists=\(toggle.exists)")
        }
    }

    @MainActor
    private func typeAndSend(_ app: XCUIApplication, _ text: String) {
        let field = element(app, "composer.field")
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(text)
        element(app, "composer.send").tap()
    }

    /// The transcript's message rows. Each message row carries a `message.` identifier.
    @MainActor
    private func replyRowCount(_ app: XCUIApplication) -> Int {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'message.'")).count
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
