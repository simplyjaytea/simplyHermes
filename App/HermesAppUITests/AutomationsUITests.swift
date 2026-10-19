import XCTest

final class AutomationsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testAutomationsTabOpensItsList() {
        let app = XCUIApplication()
        app.launchArguments += ["-HermesOnboarding", "skip"]
        app.launchArguments += ["-HermesLayout", "compact"]
        app.launch()
        // Launch opens the newest chat, which pushes over the tab bar. Back out to reach the tabs.
        XCTAssertTrue(app.navigationBars["Backup cron fix"].waitForExistence(timeout: 10))
        back(app, from: "Backup cron fix", to: "Chats")
        // The tabs are buttons in a toolbar on this layout, not tab bar buttons.
        guard let tab = visibleTab(app, "Automations") else {
            XCTFail("The tab should show Automations")
            return
        }
        tab.tap()
        XCTAssertTrue(app.navigationBars["Automations"].waitForExistence(timeout: 10))
    }

    /// Pops `current` back to `previous`. The back button is found by its identifier, wherever the layout puts it.
    /// The back swipe is the fallback. A pushed screen leaves the previous bar in the hierarchy, so the pop is
    /// confirmed by `current` going away.
    @MainActor
    private func back(_ app: XCUIApplication, from current: String, to previous: String) {
        let backButton = app.buttons["BackButton"]
        if backButton.waitForExistence(timeout: 3) {
            backButton.tap()
        }
        if !app.navigationBars[current].waitForNonExistence(timeout: 3) {
            add(XCTAttachment(string: app.debugDescription))
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        XCTAssertTrue(
            app.navigationBars[current].waitForNonExistence(timeout: 5),
            "Expected to back out of \(current) to \(previous)"
        )
    }

    /// The on-screen tab with this label. Hidden copies stay in the hierarchy and can come first, so take the
    /// one that is hittable. Polls, because the tab bar settles after a pop.
    @MainActor
    private func visibleTab(_ app: XCUIApplication, _ title: String) -> XCUIElement? {
        let copies = app.buttons.matching(NSPredicate(format: "label == %@", title))
        let deadline = Date().addingTimeInterval(10)
        repeat {
            if let tab = copies.allElementsBoundByIndex.first(where: \.isHittable) {
                return tab
            }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        return nil
    }
}
