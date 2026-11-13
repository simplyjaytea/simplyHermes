import XCTest

/// WP-43 CI gate: create and open a group chat on the testbed gateway.
///
/// CI passes the testbed URL via `TEST_RUNNER_HERMES_TESTBED_URL` (reaching the test as `HERMES_TESTBED_URL`).
/// Without a testbed or when fewer than two ready bots exist, the test is skipped with a clear reason.
final class NewGroupUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testCreateAndOpenGroupOnTestbed() throws {
        guard let url = ProcessInfo.processInfo.environment["HERMES_TESTBED_URL"] else {
            throw XCTSkip(
                "HERMES_TESTBED_URL is not set (set TEST_RUNNER_HERMES_TESTBED_URL to the testbed dashboard)"
            )
        }

        let app = XCUIApplication()
        app.launchArguments += [
            "-HermesOnboarding", "fresh",
            "-HermesLayout", "compact",
            "-HermesSection", "bots",
        ]
        app.launch()

        testbedSignIn(app, url: url)

        // Reach the Bots section
        if !app.navigationBars["Bots"].waitForExistence(timeout: 5) {
            let botsTab = app.buttons.matching(NSPredicate(format: "label == 'Bots'")).firstMatch
            if botsTab.waitForExistence(timeout: 5) {
                botsTab.tap()
            }
        }
        XCTAssertTrue(app.navigationBars["Bots"].waitForExistence(timeout: 10))

        let newMenu = element(app, "bots.newMenu")
        XCTAssertTrue(newMenu.waitForExistence(timeout: 10), "The Bots toolbar should offer the New menu")
        newMenu.tap()

        let newGroup = element(app, "bots.newGroup")
        XCTAssertTrue(newGroup.waitForExistence(timeout: 5), "The New menu should offer New Group")

        guard newGroup.isEnabled else {
            throw XCTSkip(
                "New Group is disabled: the testbed gateway needs at least two ready bots (seed ops profile)"
            )
        }
        newGroup.tap()

        XCTAssertTrue(app.navigationBars["New Group"].waitForExistence(timeout: 10))

        // Name the group
        let nameField = app.textFields["Name"]
        if nameField.waitForExistence(timeout: 3) {
            nameField.tap()
            nameField.typeText("CI Group")
        }

        // Toggle candidate bots to satisfy draft requirements
        let switches = app.switches
        for index in 0..<switches.count {
            let toggle = switches.element(boundBy: index)
            if (toggle.value as? String) == "0" {
                toggle.tap()
            }
        }

        let createButton = app.buttons["Create"]
        XCTAssertTrue(createButton.waitForExistence(timeout: 5))
        guard createButton.isEnabled else {
            throw XCTSkip("Create button is disabled: requires at least two selected bots")
        }
        createButton.tap()

        XCTAssertTrue(
            app.navigationBars["New Group"].waitForNonExistence(timeout: 10),
            "Successful creation should dismiss the New Group sheet"
        )

        // The created room appears in the roster with bots.room.<roomID>
        let roomRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'bots.room.'"))
            .firstMatch
        XCTAssertTrue(roomRow.waitForExistence(timeout: 10), "The created group should appear in the roster")
        roomRow.tap()

        // The room chat screen opens and shows the composer field
        let composer = element(app, "room.composer")
        XCTAssertTrue(
            composer.waitForExistence(timeout: 10),
            "Opening the room should show the typeable room.composer field"
        )
        XCTAssertTrue(
            element(app, "room.settings").waitForExistence(timeout: 5),
            "The room should offer Group Settings"
        )
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
