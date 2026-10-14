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

        let draft = "draft survives fold"
        let field = element(app, "composer.field")
        field.tap()
        field.typeText(draft)

        let transcript = transcriptScrollView(app)
        var anchor: String?
        for _ in 0..<8 where anchor == nil {
            transcript.swipeDown()
            anchor = lastVisibleQuestion(app)
        }
        XCTAssertNotNil(anchor, "Scrolling up should show an earlier question")

        switchLayout(app, to: "innerPortrait")
        XCTAssertTrue(app.navigationBars["Backup cron fix"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Hermes is replying"].exists, "The reply should still be streaming")
        XCTAssertEqual(element(app, "composer.field").value as? String, draft)
        if let anchor {
            XCTAssertTrue(bubble(app, anchor).waitForExistence(timeout: 5))
            XCTAssertTrue(bubble(app, anchor).isHittable, "Scroll position should survive the layout change")
        }

        switchLayout(app, to: "halfFold")
        XCTAssertTrue(element(app, "quick.stop").waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "composer.field").value as? String, draft)

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

    /// A message bubble by its text. Bubbles expose the text as their accessibility value.
    @MainActor
    private func bubble(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "value == %@ OR label == %@", text, text))
            .firstMatch
    }

    /// The lowest question on screen, used as the scroll anchor to compare across layouts.
    @MainActor
    private func lastVisibleQuestion(_ app: XCUIApplication) -> String? {
        for index in stride(from: 24, through: 1, by: -1) {
            let text = "Question \(index) about backup cron fix"
            let element = bubble(app, text)
            if element.exists && element.isHittable {
                return text
            }
        }
        return nil
    }
}
