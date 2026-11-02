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

    /// Positive control: the trap must see a real connection at every transport, or the zero a local chat reports means
    /// nothing. The probe opens one connection per site; each site must read at least 1.
    @MainActor
    func testNetworkTrapCountsARealConnectionAtEverySite() {
        let app = XCUIApplication()
        app.launchArguments += ["-HermesOnboarding", "skip", "-uiTestNetworkTrap", "-uiTestNetworkProbe"]
        app.launch()

        let sites = element(app, "uiTest.networkSites")
        XCTAssertTrue(sites.waitForExistence(timeout: 15), "The trap readout should be in the shell")
        // Wait until every site reads 1 or more. A site can count more than one connection (`intercepted` does), so the
        // pattern accepts any count from 1 up, and not 0.
        let atLeastOne = Self.probedSites.map { site in
            NSPredicate(format: "label MATCHES %@", ".*\\b\(site)=[1-9][0-9]*\\b.*")
        }
        let counted = XCTNSPredicateExpectation(
            predicate: NSCompoundPredicate(andPredicateWithSubpredicates: atLeastOne), object: sites)
        _ = XCTWaiter().wait(for: [counted], timeout: 30)
        let counts = Self.counts(in: sites.label)
        for site in Self.probedSites {
            XCTAssertGreaterThanOrEqual(
                counts[site] ?? 0, 1, "\(site) should be counted; last readout: \(sites.label)")
        }
        app.terminate()
    }

    private static let probedSites = ["http", "websocket", "terminal", "ssh", "download", "intercepted"]

    /// Parses the readout (`http=1 websocket=2 ...`) into one count per site.
    private static func counts(in readout: String) -> [String: Int] {
        var counts: [String: Int] = [:]
        for pair in readout.split(separator: " ") {
            let parts = pair.split(separator: "=")
            if parts.count == 2, let value = Int(parts[1]) { counts[String(parts[0])] = value }
        }
        return counts
    }

    @MainActor
    func testLocalChatWithNoServerAnswersOnDeviceAndKeepsItsMessages() {
        // `-HermesOnboarding skip` gives no server and keeps the welcome screen away. Only `-uiTestPersistentCache`
        // puts the chat list on disk, so the relaunch below finds the chat. The first launch also resets that file.
        let app = XCUIApplication()
        app.launchArguments += [
            "-HermesOnboarding", "skip",
            "-chatModeDefault", "local",
            "-uiTestNetworkTrap",
            "-uiTestLocalExecutor=\(fakeName)",
            "-uiTestPersistentCache",
            "-uiTestResetCache",
        ]
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

        // The relaunch keeps the same arguments, minus the reset: the saved chat must survive.
        app.terminate()
        app.launchArguments.removeAll { $0 == "-uiTestResetCache" }
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
