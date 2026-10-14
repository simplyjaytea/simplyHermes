import XCTest

final class HermesAppUITests: XCTestCase {
    @MainActor
    func testLaunchShowsRoot() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["simplyHermes"].waitForExistence(timeout: 10))
    }
}
