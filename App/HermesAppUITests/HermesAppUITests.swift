import XCTest

final class HermesAppUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchOpensChatFirst() {
        let app = XCUIApplication()
        app.launchArguments += ["-HermesLayout", "compact"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Backup cron fix"].waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, "transcript").exists)
    }

    @MainActor
    func testInnerScreenShowsSidebar() {
        let app = XCUIApplication()
        app.launchArguments += ["-HermesLayout", "innerPortrait"]
        app.launch()
        XCTAssertTrue(element(app, "transcript").waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, "tab.backup").exists, "The open chat should show in the tab strip")
    }

    /// WP-21 CI gate: change layout mid-stream, as folding and unfolding do,
    /// and check the session, scroll position and draft survive.
    @MainActor
    func testFoldMidStreamKeepsSessionScrollAndDraft() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-HermesLayout", "compact",
            "-HermesDebugLayoutSwitcher", "YES",
            "-HermesDemo", "stream",
        ]
        app.launch()

        XCTAssertTrue(app.navigationBars["Backup cron fix"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Hermes is replying"].waitForExistence(timeout: 5))

        // Scroll up before the keyboard shows, so the swipe lands on the transcript and not on the keyboard.
        let transcript = transcriptScrollView(app)
        let beforeSwipes = app.debugDescription
        for _ in 0..<3 {
            transcript.swipeDown(velocity: .fast)
        }
        // The anchor is saved once the scroll comes to rest.
        let settled = NSPredicate(format: "label BEGINSWITH 'backup-'")
        _ = XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: settled, object: element(app, "debug.scrollAnchor"))],
            timeout: 5
        )
        let anchor = scrollAnchor(app)
        if !anchor.hasPrefix("backup-") {
            add(XCTAttachment(string: beforeSwipes))
            add(XCTAttachment(string: app.debugDescription))
        }
        XCTAssertTrue(anchor.hasPrefix("backup-"), "Scrolling up should anchor on an earlier message, got \(anchor)")

        let draft = "draft survives fold"
        let field = element(app, "composer.field")
        field.tap()
        field.typeText(draft)
        XCTAssertEqual(scrollAnchor(app), anchor, "Showing the keyboard should keep the scroll position")

        switchLayout(app, to: "innerPortrait")
        XCTAssertTrue(app.navigationBars["Backup cron fix"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Hermes is replying"].exists, "The reply should still be streaming")
        XCTAssertEqual(element(app, "composer.field").value as? String, draft)
        XCTAssertEqual(scrollAnchor(app), anchor, "Scroll position should survive the layout change")

        switchLayout(app, to: "halfFold")
        XCTAssertTrue(element(app, "quick.stop").waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "composer.field").value as? String, draft)
        XCTAssertEqual(scrollAnchor(app), anchor)

        switchLayout(app, to: "compact")
        XCTAssertTrue(app.navigationBars["Backup cron fix"].waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "composer.field").value as? String, draft)
    }

    /// Reports scroll hitch time in the test results, so smoothness regressions show up in CI.
    @MainActor
    func testTranscriptScrollHitches() {
        let app = XCUIApplication()
        app.launchArguments += ["-HermesLayout", "compact"]
        app.launch()
        let transcript = transcriptScrollView(app)
        XCTAssertTrue(transcript.waitForExistence(timeout: 10))
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric], options: options) {
            transcript.swipeDown(velocity: .fast)
            transcript.swipeUp(velocity: .fast)
        }
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func switchLayout(_ app: XCUIApplication, to layout: String) {
        let menu = element(app, "debugLayoutMenu")
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        let item = app.buttons[layout]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()
    }

    /// The chat's scroll view. Falls back to the first scroll view if the identifier is not exposed.
    @MainActor
    private func transcriptScrollView(_ app: XCUIApplication) -> XCUIElement {
        let byID = app.scrollViews["transcript"]
        return byID.waitForExistence(timeout: 5) ? byID : app.scrollViews.firstMatch
    }

    /// The selected chat's scroll anchor, read from the debug overlay.
    @MainActor
    private func scrollAnchor(_ app: XCUIApplication) -> String {
        let label = element(app, "debug.scrollAnchor")
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        return label.label
    }
}
