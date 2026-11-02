import XCTest

/// App update banner: a stub feed on the command line (`-HermesAppUpdateFeedHex`) offers a newer build. Update
/// records the install link instead of opening Safari (`-HermesAppUpdateStubOpen`), and Later hides the banner across
/// a relaunch. Settings › About shows the version and Check for updates.
final class AppUpdateUITests: XCTestCase {
    private static let installURL = "https://www.signulous.com/dashboard"
    private static let feed = """
        {"version":"9.0.0-alpha.99","build":99,"installURL":"\(installURL)","notes":"Stub build for UI tests"}
        """

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testBannerOffersTheUpdateAndOpensTheInstallPage() {
        let app = launch(reset: true)
        let banner = element(app, "appUpdate.banner")
        XCTAssertTrue(banner.waitForExistence(timeout: 15), "A newer build in the feed should show the banner")
        XCTAssertTrue(app.staticTexts["simplyHermes 9.0.0-alpha.99 is available."].exists)
        XCTAssertTrue(app.staticTexts["Stub build for UI tests"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "app-update-banner"
        shot.lifetime = .keepAlways
        add(shot)

        element(app, "appUpdate.update").tap()
        let opened = element(app, "appUpdate.opened")
        XCTAssertTrue(opened.waitForExistence(timeout: 5), "Update should call the URL opener")
        XCTAssertEqual(opened.label, Self.installURL)
    }

    @MainActor
    func testLaterHidesTheBannerAcrossARelaunch() {
        let app = launch(reset: true)
        XCTAssertTrue(element(app, "appUpdate.banner").waitForExistence(timeout: 15))
        element(app, "appUpdate.later").tap()
        XCTAssertTrue(element(app, "appUpdate.banner").waitForNonExistence(timeout: 5))
        app.terminate()

        let again = launch(reset: false)
        XCTAssertTrue(again.navigationBars["Chats"].waitForExistence(timeout: 10))
        XCTAssertFalse(
            element(again, "appUpdate.banner").waitForExistence(timeout: 5), "Later should hold for the same build")
    }

    @MainActor
    func testSettingsAboutShowsTheVersionAndChecksForUpdates() {
        let app = launch(reset: true)
        XCTAssertTrue(element(app, "appUpdate.banner").waitForExistence(timeout: 15))
        guard let settings = visibleTab(app, "Settings") else {
            XCTFail("Settings tab should be present")
            return
        }
        settings.tap()
        let version = element(app, "settings.appVersion")
        for _ in 0..<6 where !version.exists { app.swipeUp() }
        XCTAssertTrue(version.waitForExistence(timeout: 5))
        let check = element(app, "settings.checkForAppUpdates")
        XCTAssertTrue(check.exists)
        check.tap()
        XCTAssertTrue(element(app, "settings.installAppUpdate").waitForExistence(timeout: 10))
        XCTAssertFalse(element(app, "settings.appUpdateError").exists, "A good feed shows no error")
    }

    // MARK: Helpers

    @MainActor
    private func launch(reset: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        let hex = Data(Self.feed.utf8).map { String(format: "%02x", $0) }.joined()
        app.launchArguments += ["-HermesOnboarding", "skip", "-HermesLayout", "compact"]
        app.launchArguments += ["-HermesAppUpdateFeedHex", hex, "-HermesAppUpdateStubOpen", "YES"]
        app.launchArguments += ["-HermesAppUpdateReset", reset ? "YES" : "NO"]
        app.launch()
        // The app may open the first chat; the banner sits above the chat list.
        let back = app.navigationBars.buttons["Chats"]
        if back.waitForExistence(timeout: 5) { back.tap() }
        return app
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func visibleTab(_ app: XCUIApplication, _ title: String) -> XCUIElement? {
        let copies = app.buttons.matching(NSPredicate(format: "label == %@", title))
        let deadline = Date().addingTimeInterval(5)
        repeat {
            if let tab = copies.allElementsBoundByIndex.first(where: { $0.isHittable }) { return tab }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        return nil
    }
}
