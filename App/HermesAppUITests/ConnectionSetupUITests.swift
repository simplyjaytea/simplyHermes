import XCTest

/// WP-22 CI gate: add the WP-03 testbed gateway from the welcome screen and pass Test.
///
/// CI starts the testbed dashboard on the Mac runner and passes its URL as `TEST_RUNNER_HERMES_TESTBED_URL`
/// (it reaches the test as `HERMES_TESTBED_URL`). Without it the gateway test is skipped.
final class ConnectionSetupUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testAddTestbedGatewayAndPassTest() throws {
        let url = try XCTUnwrap(
            ProcessInfo.processInfo.environment["HERMES_TESTBED_URL"],
            "Set TEST_RUNNER_HERMES_TESTBED_URL to the testbed dashboard")
        let app = XCUIApplication()
        app.launchArguments += ["-HermesOnboarding", "fresh", "-HermesLayout", "compact"]
        app.launch()

        let addGateway = element(app, "welcome.addGateway")
        XCTAssertTrue(addGateway.waitForExistence(timeout: 10))
        addGateway.tap()

        let field = element(app, "connection.url")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(url)

        // The app reads /api/status and picks Password for the testbed's basic login.
        let username = element(app, "connection.username")
        XCTAssertTrue(username.waitForExistence(timeout: 10), "Password sign-in should be picked from the probe")
        XCTAssertTrue(element(app, "connection.basicAuthTip").exists)
        username.tap()
        username.typeText("tester")
        let password = element(app, "connection.password")
        password.tap()
        password.typeText("testbed-password")

        let test = element(app, "connection.test")
        if !test.isHittable { app.swipeUp() }
        test.tap()
        let passed = element(app, "connection.testPassed")
        if !passed.waitForExistence(timeout: 30) {
            add(XCTAttachment(screenshot: app.screenshot()))
            XCTFail("Test did not pass: \(element(app, "connection.testFailed").label)")
        }

        element(app, "connection.save").tap()
        // Saving the first server opens the app on the first chat; the chat list shows the server switcher.
        XCTAssertTrue(app.navigationBars["Backup cron fix"].waitForExistence(timeout: 10))
        app.navigationBars.buttons["Chats"].tap()
        XCTAssertTrue(element(app, "serverSwitcher").waitForExistence(timeout: 5))
    }

    @MainActor
    func testWelcomeShowsChoicesAndHTTPRule() {
        let app = XCUIApplication()
        app.launchArguments += ["-HermesOnboarding", "fresh", "-HermesLayout", "compact"]
        app.launch()

        XCTAssertTrue(element(app, "welcome.addGateway").waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, "welcome.addSSH").exists)
        XCTAssertTrue(element(app, "welcome.scan").exists)

        element(app, "welcome.addGateway").tap()
        let field = element(app, "connection.url")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("http://192.168.1.20:9119")
        XCTAssertTrue(element(app, "connection.httpWarning").waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()

        element(app, "welcome.addSSH").tap()
        XCTAssertTrue(element(app, "connection.publicKey").waitForExistence(timeout: 5))
        XCTAssertTrue((element(app, "connection.publicKey").label).hasPrefix("ssh-ed25519 "))
        XCTAssertEqual(element(app, "connection.faceID").value as? String, "1", "Face ID is on by default for SSH")
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
