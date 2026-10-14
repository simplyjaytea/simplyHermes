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

        let transcript = element(app, "transcript")
        for _ in 0..<4 {
            transcript.swipeDown()
        }
        let anchor = try? XCTUnwrap(lastVisibleQuestion(app))
        XCTAssertNotNil(anchor, "Scrolling up should show an earlier question")

        switchLayout(app, to: "innerPortrait")
        XCTAssertTrue(app.navigationBars["Backup cron fix"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Hermes is replying"].exists, "The reply should still be streaming")
        XCTAssertEqual(element(app, "composer.field").value as? String, draft)
        if let anchor {
            XCTAssertTrue(app.staticTexts[anchor].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts[anchor].isHittable, "Scroll position should survive the layout change")
        }

        switchLayout(app, to: "halfFold")
        XCTAssertTrue(element(app, "quick.stop").waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "composer.field").value as? String, draft)

        switchLayout(app, to: "compact")
        XCTAssertTrue(app.navigationBars["Backup cron fix"].waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "composer.field").value as? String, draft)
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func switchLayout(_ app: XCUIApplication, to layout: String) {
        let menu = element(app, "debugLayoutMenu")
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        let item = app.buttons[layout]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()
    }

    /// The lowest question on screen, used as the scroll anchor to compare across layouts.
    private func lastVisibleQuestion(_ app: XCUIApplication) -> String? {
        for index in stride(from: 24, through: 1, by: -1) {
            let label = "Question \(index) about backup cron fix"
            let text = app.staticTexts[label]
            if text.exists && text.isHittable {
                return label
            }
        }
        return nil
    }
}
