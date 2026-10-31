import XCTest

final class NewGroupUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testBotsNewGroupOpensCreationSheet() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-HermesOnboarding", "skip",
            "-HermesLayout", "compact",
            "-HermesSection", "bots",
        ]
        app.launch()

        XCTAssertTrue(app.navigationBars["Bots"].waitForExistence(timeout: 10))

        let newMenu = app.buttons["bots.newMenu"]
        XCTAssertTrue(newMenu.waitForExistence(timeout: 5))
        newMenu.tap()

        let newGroup = app.buttons["bots.newGroup"]
        XCTAssertTrue(newGroup.waitForExistence(timeout: 5))

        if newGroup.isEnabled {
            newGroup.tap()

            XCTAssertTrue(app.navigationBars["New Group"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["Create"].exists)

            app.buttons["Cancel"].tap()
            XCTAssertTrue(app.navigationBars["New Group"].waitForNonExistence(timeout: 5))
        }
    }
}
