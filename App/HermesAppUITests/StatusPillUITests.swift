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
        let repliesBefore = replyRowIDs(app)

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
        XCTAssertEqual(
            replyRowIDs(app).subtracting(repliesBefore), [],
            "No assistant row should appear while the gateway is stopped")
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
        let repliesBefore = replyRowIDs(app)
        // What the composer and the chat held right after typing, for the message of a failed draft check below.
        let typed = "field=\(field.value as? String ?? "nil") \(element(app, "uiTest.chatStatus").label)"

        let banner = element(app, "chat.outageBanner")
        if !banner.waitForExistence(timeout: 10) {
            failWithOutageState(app, "The outage banner should show while the gateway is stopped")
        }

        let tryAgain = element(app, "outage.tryAgain")
        XCTAssertTrue(tryAgain.waitForExistence(timeout: 5))
        tryAgain.tap()
        XCTAssertTrue(
            banner.waitForExistence(timeout: 10), "Try again should keep the banner while the gateway is stopped")
        XCTAssertEqual(
            replyRowIDs(app).subtracting(repliesBefore), [], "Try again must not produce an assistant row")

        let continueLocal = element(app, "outage.continueLocal")
        XCTAssertTrue(continueLocal.waitForExistence(timeout: 5))
        XCTAssertEqual(continueLocal.label, "Continue in a new Local chat")
        continueLocal.tap()

        // The compact layout pushes the new chat over the server's chat list, which has no Local rows, so no
        // `session.local-` row is on screen. The Local chat's own transcript shows that it opened.
        let local = element(app, "local.transcript")
        XCTAssertTrue(local.waitForExistence(timeout: 10), "A new Local chat should open")
        let carried = element(app, "composer.field")
        XCTAssertTrue(carried.waitForExistence(timeout: 10))
        XCTAssertEqual(
            carried.value as? String, draft, "The new Local chat should carry the draft. After typing: \(typed)")
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

        // The chat's own id, from the hidden status ("screen=<id>"), so its row is found again whatever the list's order.
        let status = element(app, "uiTest.chatStatus").label
        let chatID = try XCTUnwrap(
            status.components(separatedBy: " ").first { $0.hasPrefix("screen=") }?.dropFirst("screen=".count),
            "The hidden status should name the chat on screen: \(status)")

        // Another chat takes the screen while the gateway is down. The compact layout shows New chat on the chat list,
        // not over an open chat (run 43658919091), so go back to the list first.
        let newChat = showChatList(app)
        // The chat is listed while its message waits: by the server, or under "Waiting to send" when the server does
        // not list it. This does not tell the two apart.
        XCTAssertTrue(
            element(app, "session.\(chatID)").waitForExistence(timeout: 10),
            "A chat with a waiting message should be listed while the gateway is stopped")
        newChat.tap()
        XCTAssertTrue(element(app, "composer.field").waitForExistence(timeout: 10))

        toggleGateway(app, expecting: "Stop gateway")

        _ = showChatList(app)
        let firstChat = element(app, "session.\(chatID)")
        // The list is read from the server again once the gateway is back, so allow for the reconnect.
        XCTAssertTrue(firstChat.waitForExistence(timeout: 30), "The first chat should be listed")
        firstChat.tap()

        XCTAssertTrue(
            app.staticTexts["Waiting to send"].waitForNonExistence(timeout: 30),
            "The waiting message should send once the chat is back")
        XCTAssertEqual(
            app.staticTexts.matching(NSPredicate(format: "label == %@", draft)).count, 1,
            "The message should be delivered exactly once")
    }

    /// Moss FAIL at f6cbe43: Try again did nothing for a chat that had been connected and then lost its server. With
    /// the gateway back, Try again reconnects the chat, the pill reads Online, and the waiting message is sent once.
    /// The window is short on purpose: the Online must come from Try again, not from the connection's own backoff.
    @MainActor
    func testTryAgainReconnectsTheChatAndSendsTheWaitingMessageOnce() throws {
        let app = try launchWithTestbed()
        openLiveServerChat(app)
        toggleGateway(app, expecting: "Start gateway")
        typeAndSend(app, draft)
        if !app.staticTexts["Waiting to send"].waitForExistence(timeout: 10) {
            failWithOutageState(app, "The message should wait")
        }
        XCTAssertTrue(element(app, "chat.outageBanner").waitForExistence(timeout: 5), "The outage banner should show")

        toggleGateway(app, expecting: "Stop gateway")
        let tryAgain = element(app, "outage.tryAgain")
        // The connection also retries by itself when the network path comes back, and on a fast run it is Online
        // before Try again can be tapped: the banner is then gone, with nothing left to tap (run 43676167671). Try
        // again is tapped when it is still offered. Either way the chat must be Online in the short window below, and
        // the waiting message must be sent once.
        if tryAgain.waitForExistence(timeout: 5) { tryAgain.tap() }

        let pill = element(app, "chat.pill")
        let online = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label BEGINSWITH 'Online chat.'"), object: pill)
        if XCTWaiter().wait(for: [online], timeout: 8) != .completed {
            failWithOutageState(app, "Try again should reconnect the chat and show Online")
        }
        XCTAssertTrue(
            app.staticTexts["Waiting to send"].waitForNonExistence(timeout: 30),
            "The waiting message should send once Try again has reconnected the chat")
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
            "fields=\(app.descendants(matching: .any).matching(identifier: "composer.field").count)",
            "field=\(element(app, "composer.field").value as? String ?? "nil")",
            "alerts=\(app.alerts.allElementsBoundByIndex.map(\.label))",
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

        // The shared sign-in steps, including Remember password: the saved server must be able to sign in again.
        testbedSignIn(app, url: url)
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
        // While the server connects, the first send is refused: the app shows a "Chat not started" alert and the text
        // stays in the composer. The alert is modal, so every later tap lands on it and is lost until it is dismissed.
        // Dismiss it, then send again, until the chat is live.
        let pill = element(app, "chat.pill")
        var attempts = 1
        var refusals: [String] = []
        while !pill.waitForExistence(timeout: 10), attempts < 6 {
            let alert = app.alerts["Chat not started"]
            if alert.exists {
                refusals.append(alert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " / "))
                alert.buttons["OK"].tap()
            }
            let send = element(app, "composer.send")
            if send.exists, send.isEnabled { send.tap() }
            attempts += 1
        }
        // Positive check before any outage: the pill is its own element, and the chat is connected.
        if !pill.exists {
            failWithChatState(
                app, "The status pill should be an element of its own after \(attempts) sends, refusals=\(refusals)")
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
        // Connect only starts the connection, and a first message sent before it finishes is refused ("... is not
        // connected", run 43198484235: five refusals in a row, so the phase was idle or failed, not connecting). Start it
        // up to three times, and wait each time until the server's row reads Connected. The row's label combines its
        // status line, so a failure names the state the server was in.
        for _ in 0..<3 {
            if server.label.contains("Connected") { break }
            if !server.label.contains("Connecting") {
                server.press(forDuration: 1.0)
                let connect = app.buttons["Connect"]
                if connect.waitForExistence(timeout: 5) { connect.tap() }
            }
            let connected = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label CONTAINS 'Connected'"), object: server)
            _ = XCTWaiter().wait(for: [connected], timeout: 30)
        }
        if !server.label.contains("Connected") {
            XCTFail("The saved server should connect before the first message [row=\(server.label)]")
        }
        tabButton(app, "Chats").tap()
    }

    /// The on-screen tab with this label. Hidden copies of a tab stay in the hierarchy and can come first, with an
    /// infinite frame that cannot be tapped ("failed to scroll to visible"), so take the one that is hittable. Polls,
    /// because the tab bar settles after a screen change. The other UI tests do the same.
    @MainActor
    private func tabButton(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        let copies = app.buttons.matching(NSPredicate(format: "label == %@", name))
        let deadline = Date().addingTimeInterval(10)
        repeat {
            if let tab = copies.allElementsBoundByIndex.first(where: \.isHittable) { return tab }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        XCTFail("The \(name) tab should be on screen")
        return copies.firstMatch
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

    /// Shows the chat list and returns its New chat button. In the compact layout an open chat covers the list.
    ///
    /// The back control is the one the other UI tests use: the round `BackButton`, then a titled "Chats". The first
    /// button of the navigation bar is not it: over an open chat that can be the chat's own Commands button, and
    /// tapping it never reaches the list (runs 43658919091 to 43682165389 failed here on both tries). New chat has
    /// hidden copies on the Duo layout, so the one that can be tapped is taken.
    @MainActor
    private func showChatList(_ app: XCUIApplication) -> XCUIElement {
        let copies = app.buttons.matching(identifier: "shell.newChat")
        func onScreen() -> XCUIElement? { copies.allElementsBoundByIndex.first(where: \.isHittable) }
        if let newChat = onScreen() { return newChat }
        let backButton = app.buttons["BackButton"]
        if backButton.waitForExistence(timeout: 5), backButton.isHittable {
            backButton.tap()
        } else if app.navigationBars.buttons["Chats"].exists {
            app.navigationBars.buttons["Chats"].tap()
        }
        let deadline = Date().addingTimeInterval(10)
        repeat {
            if let newChat = onScreen() { return newChat }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        // Say what the screen held, so a failure here is not a guess.
        let bars = app.navigationBars.allElementsBoundByIndex.map(\.identifier)
        let barButtons = app.navigationBars.buttons.allElementsBoundByIndex.map { "\($0.identifier)|\($0.label)" }
        XCTFail(
            "The chat list should show New chat. copies=\(copies.count) backButton=\(backButton.exists) "
                + "bars=\(bars) barButtons=\(barButtons) sheets=\(app.sheets.count) keyboard=\(app.keyboards.count)")
        return copies.firstMatch
    }

    @MainActor
    private func typeAndSend(_ app: XCUIApplication, _ text: String) {
        let field = element(app, "composer.field")
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(text)
        let send = element(app, "composer.send")
        // A send button under the keyboard cannot be tapped: the tap lands on a key (run 43641154917 typed "P" and a
        // suggestion into the draft and sent nothing). Say so, with the frames, and do not tap blind.
        let keyboard = app.keyboards.firstMatch
        if keyboard.exists, keyboard.frame.intersects(send.frame) {
            add(XCTAttachment(screenshot: app.screenshot()))
            XCTFail(
                "The composer's send button is under the keyboard. send=\(send.frame) field=\(field.frame) "
                    + "keyboard=\(keyboard.frame) banner=\(element(app, "chat.outageBanner").frame) "
                    + "transcript=\(element(app, "transcript").frame) window=\(app.windows.firstMatch.frame)")
        }
        send.tap()
    }

    /// The ids of the transcript's message rows on screen. Each message row carries a `message.` identifier. A check
    /// for "no new row" compares ids, not a count: the banner takes room from the transcript, and a lazy stack drops
    /// the rows that leave the screen (run 43658919091 counted 3 before and 2 after).
    @MainActor
    private func replyRowIDs(_ app: XCUIApplication) -> Set<String> {
        // One snapshot of the whole tree. Reading each match by index failed in run 43689903785 with "No matches found
        // for Element at index 3", when a lazy row left between the count and the read.
        guard let root = try? app.snapshot() else {
            XCTFail("The app's element tree could not be read")
            return []
        }
        var ids: Set<String> = []
        var pending: [any XCUIElementSnapshot] = [root]
        while let next = pending.popLast() {
            if next.identifier.hasPrefix("message.") { ids.insert(next.identifier) }
            pending.append(contentsOf: next.children)
        }
        return ids
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
