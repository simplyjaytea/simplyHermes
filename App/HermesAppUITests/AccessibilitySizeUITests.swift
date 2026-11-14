import XCTest

/// Feature "Dynamic Type and VoiceOver pass": at the largest accessibility text size, on the outer screen and in
/// half-fold, the main controls of the chat, the chats list and Settings exist, can be tapped, and have a label.
/// Apple's audit then runs on each screen. It fails on missing descriptions of this app's own controls (the ones with
/// an accessibility identifier); everything else it finds is attached as a report, as `AccessibilityMatrixUITests`
/// does, because system views (keyboard, tab bar internals) also show up there.
///
/// Bot settings need a live server, so CI cannot open them; their layout fixes are checked by previews only.
final class AccessibilitySizeUITests: XCTestCase {
    private static let largestText = "UICTContentSizeCategoryAccessibilityXXXL"

    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor
    func testOuterScreenAtLargestText() throws {
        try check(layout: "compact")
    }

    @MainActor
    func testHalfFoldAtLargestText() throws {
        try check(layout: "halfFold")
    }

    @MainActor
    private func check(layout: String) throws {
        let app = XCUIApplication()
        app.launchArguments += ["-HermesOnboarding", "skip", "-HermesLayout", layout, "-HermesSampleChats", "YES"]
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", Self.largestText]
        app.launch()

        // Chat
        XCTAssertTrue(element(app, "transcript").waitForExistence(timeout: 15), "\(layout): the chat should open")
        assertUsable(element(app, "composer.field"), "message field", in: layout)
        let send = element(app, "composer.send")
        XCTAssertTrue(send.exists, "\(layout): the send button should exist")
        XCTAssertFalse(send.label.isEmpty, "\(layout): the send button needs a label")
        try audit(app, screen: "\(layout)-chat")

        if layout == "halfFold" {
            // Half-fold has no chat list, tab rail or Settings by design (plan Q4): transcript on top, composer and
            // the six quick actions below. Check those instead.
            for action in ["approve", "deny", "stop", "voice", "attach", "terminal"] {
                let button = element(app, "quick.\(action)")
                XCTAssertTrue(button.waitForExistence(timeout: 5), "halfFold: quick action \(action) should exist")
                XCTAssertTrue(button.isHittable, "halfFold: quick action \(action) should be on screen")
                XCTAssertFalse(button.label.isEmpty, "halfFold: quick action \(action) needs a label")
            }
            return
        }

        // Chats list. The chat is pushed; at this size its back control is the round BackButton with no title (the
        // iOS run's screenshot shows it in the right-hand rail), so try that first, then a titled "Chats".
        let backButton = app.buttons["BackButton"]
        if backButton.waitForExistence(timeout: 5), backButton.isHittable {
            backButton.tap()
        } else if app.navigationBars.buttons["Chats"].exists {
            app.navigationBars.buttons["Chats"].tap()
        }
        let newChat = app.buttons["New chat"]
        XCTAssertTrue(newChat.waitForExistence(timeout: 10), "\(layout): the chats list should be reachable")
        assertUsable(newChat, "New chat", in: layout)
        try audit(app, screen: "\(layout)-chats")

        // Settings
        // The Duo layout keeps hidden copies of "Settings" that can't be tapped, so take one that is hittable.
        let settings = hittable(app.buttons.matching(NSPredicate(format: "label == %@", "Settings")))
        XCTAssertNotNil(settings, "\(layout): a tappable Settings button should exist")
        settings?.tap()
        XCTAssertTrue(
            app.navigationBars["Settings"].waitForExistence(timeout: 10), "\(layout): Settings should be reachable")
        XCTAssertTrue(app.cells.firstMatch.exists, "\(layout): Settings should list its rows")
        try audit(app, screen: "\(layout)-settings")
    }

    @MainActor
    private func assertUsable(_ control: XCUIElement, _ name: String, in layout: String) {
        XCTAssertTrue(control.waitForExistence(timeout: 5), "\(layout): \(name) should exist")
        XCTAssertTrue(control.isHittable, "\(layout): \(name) should be on screen and tappable")
        XCTAssertFalse(control.label.isEmpty && control.identifier.isEmpty, "\(layout): \(name) needs a label")
    }

    /// Runs the audit. Missing descriptions on this app's own controls fail; all findings go into the report.
    @MainActor
    private func audit(_ app: XCUIApplication, screen: String) throws {
        var findings: [String] = []
        try app.performAccessibilityAudit(for: [.dynamicType, .textClipped, .sufficientElementDescription]) { issue in
            let identifier = issue.element?.identifier ?? ""
            let name = identifier.isEmpty ? (issue.element?.label ?? "unknown element") : identifier
            findings.append("\(issue.auditType.rawValue)\t\(name)\t\(issue.compactDescription)")
            // Our controls carry identifiers; one without a description is a real miss.
            let ours = !identifier.isEmpty && !identifier.hasPrefix("_")
            return !(ours && issue.auditType == .sufficientElementDescription)
        }
        let report = XCTAttachment(string: findings.isEmpty ? "No findings" : findings.joined(separator: "\n"))
        report.name = "\(screen) audit"
        report.lifetime = .keepAlways
        add(report)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = screen
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// The first hittable element of `query`, polling for up to 10 s while the tab bar settles.
    @MainActor
    private func hittable(_ query: XCUIElementQuery) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(10)
        repeat {
            if let match = query.allElementsBoundByIndex.first(where: \.isHittable) { return match }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        return nil
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
