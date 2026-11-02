import XCTest

final class HermesAppUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchOpensChatFirst() {
        let app = XCUIApplication()
        app.launchArguments += ["-HermesOnboarding", "skip", "-HermesSampleChats", "YES"]
        app.launchArguments += ["-HermesLayout", "compact"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Backup cron fix"].waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, "transcript").exists)
    }

    @MainActor
    func testInnerScreenShowsSidebar() {
        let app = XCUIApplication()
        app.launchArguments += ["-HermesOnboarding", "skip", "-HermesSampleChats", "YES"]
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
        app.launchArguments += ["-HermesOnboarding", "skip", "-HermesSampleChats", "YES"]
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

        // The inner screen names the chat in its tab strip, not a navigation bar.
        switchLayout(app, to: "innerPortrait", until: element(app, "tab.backup"))
        XCTAssertTrue(app.staticTexts["Hermes is replying"].exists, "The reply should still be streaming")
        XCTAssertEqual(element(app, "composer.field").value as? String, draft)
        XCTAssertEqual(scrollAnchor(app), anchor, "Scroll position should survive the layout change")

        switchLayout(app, to: "halfFold", until: element(app, "quick.stop"))
        XCTAssertEqual(element(app, "composer.field").value as? String, draft)
        XCTAssertEqual(scrollAnchor(app), anchor)

        switchLayout(app, to: "compact", until: app.navigationBars["Backup cron fix"])
        XCTAssertEqual(element(app, "composer.field").value as? String, draft)
    }

    /// Reports scroll hitch time in the test results, so smoothness regressions show up in CI.
    @MainActor
    func testTranscriptScrollHitches() {
        let app = XCUIApplication()
        app.launchArguments += ["-HermesOnboarding", "skip", "-HermesSampleChats", "YES"]
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

    /// Switches the debug layout and waits for `marker`, which only the new layout shows. With the keyboard up, the
    /// first tap on the menu can be taken by the keyboard dismissal and the layout never changes (runs 41345522916,
    /// 41400876569, 41407961940). So a switch that did not happen is tried once more. The test's assertions on the
    /// draft, the stream and the scroll position are unchanged.
    @MainActor
    private func switchLayout(_ app: XCUIApplication, to layout: String, until marker: XCUIElement) {
        var problem = ""
        for attempt in 1...2 {
            problem = pickFromLayoutMenu(app, layout) ?? "the layout did not change"
            if marker.waitForExistence(timeout: 5) { return }
            if attempt == 1 { add(XCTAttachment(string: app.debugDescription)) }
        }
        XCTFail("Switching to \(layout) did not show its layout after two tries: \(problem)")
    }

    /// Opens the debug layout menu and taps `layout`. Returns what went wrong, or nil when the item was tapped. It
    /// records no failure itself, so a first try that misses can be retried.
    @MainActor
    private func pickFromLayoutMenu(_ app: XCUIApplication, _ layout: String) -> String? {
        let menu = element(app, "debugLayoutMenu")
        guard menu.waitForExistence(timeout: 5) else { return "the debug layout menu is missing" }
        menu.tap()
        let item = app.buttons[layout]
        guard item.waitForExistence(timeout: 5) else { return "the \(layout) item did not appear" }
        // The item can exist before the menu lays it out. Wait until it can be tapped.
        let hittable = NSPredicate(format: "isHittable == true")
        let ready = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: hittable, object: item)], timeout: 10)
        guard ready == .completed else { return "the \(layout) item was not tappable" }
        item.tap()
        return nil
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
