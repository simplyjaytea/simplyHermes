import XCTest

/// Shared steps for UI tests that run against the CI testbed (`HERMES_TESTBED_URL`). One copy, so a fix to a flaky
/// step (watch row 106: "Password sign-in should be picked from the probe") lands once.
extension XCTestCase {
    /// The WP-22 connection steps: the welcome screen, the testbed URL, the basic login, Test, then Save.
    @MainActor
    func testbedSignIn(_ app: XCUIApplication, url: String) {
        let addGateway = testbedElement(app, "welcome.addGateway")
        XCTAssertTrue(addGateway.waitForExistence(timeout: 10))
        addGateway.tap()

        let field = testbedElement(app, "connection.url")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(url)

        let username = testbedElement(app, "connection.username")
        XCTAssertTrue(username.waitForExistence(timeout: 10), "Password sign-in should be picked from the probe")
        username.tap()
        username.typeText("tester")
        let password = testbedElement(app, "connection.password")
        password.tap()
        password.typeText("testbed-password")

        // The app keeps a gateway password only when "Remember password" is on. Without it the saved server has no
        // password, and connecting it ends in "Sign in again" (run 43495829201). The wizard's own check passes either way.
        testbedRememberPassword(app)

        let test = testbedElement(app, "connection.test")
        if !test.isHittable { app.swipeUp() }
        test.tap()
        XCTAssertTrue(testbedElement(app, "connection.testPassed").waitForExistence(timeout: 30))

        testbedElement(app, "connection.save").tap()
        XCTAssertTrue(testbedElement(app, "welcome.addGateway").waitForNonExistence(timeout: 10))
    }

    /// Turns on "Remember password" in the connection form, so the saved server can sign in again by itself.
    ///
    /// A tap on the middle of a form toggle lands on its title, which does not flip the switch (run 43593302488: ten
    /// tests read "0" after the tap). So this taps the switch itself: the inner switch when the toggle reports one,
    /// else the trailing end of the row, and waits for the value after each try.
    @MainActor
    func testbedRememberPassword(_ app: XCUIApplication) {
        var remember = testbedElement(app, "connection.rememberPassword")
        if !remember.waitForExistence(timeout: 3) {
            // A build without the identifier: find the toggle by its title.
            remember =
                app.descendants(matching: .any)
                .matching(NSPredicate(format: "label == 'Remember password'")).firstMatch
        }
        if !remember.waitForExistence(timeout: 2) || !remember.isHittable { app.swipeUp() }
        XCTAssertTrue(remember.waitForExistence(timeout: 5), "The form should offer Remember password")
        let isOn = NSPredicate(format: "value == '1'")
        func settled() -> Bool {
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: isOn, object: remember)], timeout: 2)
                == .completed
        }
        if (remember.value as? String) != "1" {
            let inner = remember.switches.firstMatch
            if inner.exists {
                inner.tap()
            } else {
                remember.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            }
            if !settled() {
                // Still off, so the first tap did nothing. Try the other way once.
                if inner.exists {
                    remember.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
                } else {
                    remember.tap()
                }
                _ = settled()
            }
        }
        XCTAssertEqual(
            remember.value as? String, "1", "Remember password should be on, or the saved server can't sign in")
    }

    /// Waits until the saved server's row in Settings › Servers reads Connected, starting the connection up to three
    /// times, then goes back to Chats. A first message sent before that is refused ("… is not connected", run
    /// 43198484235). Same wait as StatusPillUITests on #123.
    @MainActor
    func testbedWaitUntilConnected(_ app: XCUIApplication) {
        testbedHittableButton(app, "Settings").tap()
        let servers = testbedElement(app, "settings.servers")
        XCTAssertTrue(servers.waitForExistence(timeout: 10), "Settings should list the servers")
        servers.tap()
        let server = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'server.'")).firstMatch
        XCTAssertTrue(server.waitForExistence(timeout: 10), "The saved server should be listed")
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
        XCTAssertTrue(server.label.contains("Connected"), "The testbed should connect [row=\(server.label)]")
        testbedHittableButton(app, "Chats").tap()
    }

    /// Opens a testbed chat: the first listed one, or a new one made by sending a message the fake LLM answers. So a
    /// test that needs a server chat never skips because the testbed happened to have none.
    @MainActor
    func testbedOpenAChat(_ app: XCUIApplication) {
        let session = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'session.'"))
            .firstMatch
        if session.waitForExistence(timeout: 10) {
            session.tap()
            return
        }
        testbedHittableButton(app, "shell.newChat", byIdentifier: true).tap()
        let field = testbedElement(app, "composer.field")
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("hello [[scenario:text]]")
        testbedElement(app, "composer.send").tap()
        let reply = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'fake LLM'")).firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 90), "The testbed's fake LLM should answer the new chat")
    }

    /// The on-screen copy of a button. Hidden copies stay in the hierarchy on the Duo layout and can come first, with a
    /// frame that cannot be tapped, so take one that is hittable. Polls while the tab bar settles.
    @MainActor
    func testbedHittableButton(_ app: XCUIApplication, _ name: String, byIdentifier: Bool = false) -> XCUIElement {
        let format = byIdentifier ? "identifier == %@" : "label == %@"
        let copies = app.buttons.matching(NSPredicate(format: format, name))
        let deadline = Date().addingTimeInterval(10)
        repeat {
            if let match = copies.allElementsBoundByIndex.first(where: \.isHittable) { return match }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        XCTFail("\(name) should be on screen")
        return copies.firstMatch
    }

    @MainActor
    func testbedElement(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
