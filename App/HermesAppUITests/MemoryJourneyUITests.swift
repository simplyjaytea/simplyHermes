import XCTest

/// WP-52: the memory screen opens from the `-HermesScreen memory` launch route and shows its list. With no server
/// saved, as on a fresh simulator, the list is replaced by the empty state, so either one counts. The test needs no
/// server, so it does not depend on the testbed (WP-03).
final class MemoryJourneyUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testMemoryScreenShowsListOrEmptyState() {
        let app = XCUIApplication()
        app.launchArguments += ["-HermesScreen", "memory", "-HermesOnboarding", "skip", "-HermesLayout", "compact"]
        app.launch()

        let shown = NSPredicate(format: "identifier IN %@", ["memory.list", "memory.empty"])
        let screen = app.descendants(matching: .any).matching(shown).firstMatch
        XCTAssertTrue(
            screen.waitForExistence(timeout: 20), "memory list or empty state missing:\n\(app.debugDescription)")
        XCTAssertTrue(
            app.navigationBars["Memory"].waitForExistence(timeout: 5),
            "navigation title missing:\n\(app.debugDescription)")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "memory-journey"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
