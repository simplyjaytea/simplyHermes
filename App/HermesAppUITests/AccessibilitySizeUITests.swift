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

        // Chats list (compact pushes the chat; the half-fold shell keeps the list in the sidebar or a tab)
        let back = app.navigationBars.buttons["Chats"]
        if back.exists { back.tap() }
        let newChat = app.buttons["New chat"]
        if newChat.waitForExistence(timeout: 5) {
            assertUsable(newChat, "New chat", in: layout)
            try audit(app, screen: "\(layout)-chats")
        }

        // Settings
        let settingsTab = app.tabBars.buttons["Settings"]
        let settingsRow = app.buttons["Settings"].firstMatch
        if settingsTab.exists {
            settingsTab.tap()
        } else if settingsRow.exists {
            settingsRow.tap()
        }
        if app.navigationBars["Settings"].waitForExistence(timeout: 5) {
            let firstRow = app.cells.firstMatch
            XCTAssertTrue(firstRow.exists, "\(layout): Settings should list its rows")
            try audit(app, screen: "\(layout)-settings")
        }
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

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
