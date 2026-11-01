import XCTest

/// Feature "Update available": a fake feed on the command line (`-HermesUpdateFeedHex`) offers a newer build. Update
/// opens the release page (stubbed: the link shows as text instead of Safari) and Later hides the banner across a
/// relaunch.
final class AppUpdateUITests: XCTestCase {
    private static let releaseURL = "https://github.com/simplyjaytea/simplyHermes/releases/tag/v9.0.0-alpha.99"
    private static let feed = """
        {"version":"9.0.0-alpha.99","build":99,"releaseURL":"\(releaseURL)","notes":"Fake build for UI tests"}
        """

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testBannerOffersTheUpdateAndOpensTheReleasePage() {
        let app = launch(reset: true)
        let banner = element(app, "appUpdate.banner")
        XCTAssertTrue(banner.waitForExistence(timeout: 15), "A newer build in the feed should show the banner")
        XCTAssertTrue(app.staticTexts["simplyHermes 9.0.0-alpha.99 is available"].exists)

        element(app, "appUpdate.update").tap()
        let opened = element(app, "appUpdate.opened")
        XCTAssertTrue(opened.waitForExistence(timeout: 5))
        XCTAssertEqual(opened.label, Self.releaseURL)
    }

    @MainActor
    func testLaterHidesTheBannerAcrossARelaunch() {
        let app = launch(reset: true)
        XCTAssertTrue(element(app, "appUpdate.banner").waitForExistence(timeout: 15))
        element(app, "appUpdate.later").tap()
        XCTAssertFalse(element(app, "appUpdate.banner").waitForExistence(timeout: 2))
        app.terminate()

        let again = launch(reset: false)
        XCTAssertTrue(again.navigationBars["Chats"].waitForExistence(timeout: 10))
        XCTAssertFalse(
            element(again, "appUpdate.banner").waitForExistence(timeout: 5), "Later should hold for the same build")
    }

    // MARK: Helpers

    @MainActor
    private func launch(reset: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        let hex = Data(Self.feed.utf8).map { String(format: "%02x", $0) }.joined()
        app.launchArguments += ["-HermesOnboarding", "skip", "-HermesLayout", "compact", "-HermesSampleChats", "YES"]
        app.launchArguments += ["-HermesUpdateFeedHex", hex, "-HermesUpdateStubOpen", "YES"]
        app.launchArguments += ["-HermesUpdateReset", reset ? "YES" : "NO"]
        app.launch()
        // The app opens the first chat; the banner sits above the chat list.
        let back = app.navigationBars.buttons["Chats"]
        if back.waitForExistence(timeout: 10) { back.tap() }
        return app
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
