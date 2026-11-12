import XCTest

/// Row 122: the unfolded layout's sidebar has a chat search. The home-screen Search chats action opens it, and typing
/// filters the sidebar's chats. Sample chats, no server, so nothing here needs the testbed.
final class SidebarSearchUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testSearchChatsOpensTheSidebarSearchAndFiltersIt() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-HermesOnboarding", "skip", "-HermesLayout", "innerPortrait", "-HermesSampleChats", "YES",
            "-HermesQuickAction", "searchChats",
        ]
        app.launch()

        let search = app.searchFields["Search chats"]
        XCTAssertTrue(search.waitForExistence(timeout: 15), "The sidebar has a chat search")
        let focused = expectation(for: NSPredicate(format: "hasKeyboardFocus == true"), evaluatedWith: search)
        XCTAssertEqual(XCTWaiter.wait(for: [focused], timeout: 10), .completed, "Search chats opens it, ready to type")

        let router = element(app, "session.router")
        let blog = element(app, "session.blog")
        XCTAssertTrue(router.waitForExistence(timeout: 5))
        XCTAssertTrue(blog.exists)
        search.typeText("firmware")
        XCTAssertTrue(blog.waitForNonExistence(timeout: 5), "A chat that doesn't match leaves the list")
        XCTAssertTrue(router.exists, "The matching chat stays")
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
