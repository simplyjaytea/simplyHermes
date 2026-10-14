import XCTest

/// WP-02 CI gate: the posture debug view builds, opens and prints its labels on whichever simulator CI has.
final class PostureDebugUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testDebugViewPrintsPostureAndScreenLabels() {
        let app = XCUIApplication()
        app.launchArguments += ["-HermesScreen", "postureDebug"]
        app.launch()

        let posture = label(app, "posture")
        XCTAssertTrue(posture.waitForExistence(timeout: 10))
        // Without a Duo hinge the posture falls back to flat.
        XCTAssertTrue(["flat", "halfFolded", "tent"].contains(posture.label), "posture was \(posture.label)")
        XCTAssertFalse(label(app, "hinge.status").label.isEmpty)
        XCTAssertFalse(label(app, "sizeClass.horizontal").label.isEmpty)
        XCTAssertTrue(label(app, "size").label.contains("×"))
        XCTAssertTrue(label(app, "regions.count").exists)

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "posture-debug"
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    func testForcedPostureShowsInDebugView() {
        let app = XCUIApplication()
        app.launchArguments += ["-HermesScreen", "postureDebug", "-HermesPosture", "tent"]
        app.launch()
        let posture = label(app, "posture")
        XCTAssertTrue(posture.waitForExistence(timeout: 10))
        let tent = NSPredicate(format: "label == 'tent'")
        let wait = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: tent, object: posture)], timeout: 5)
        XCTAssertEqual(wait, .completed, "posture was \(posture.label)")
    }

    @MainActor
    private func label(_ app: XCUIApplication, _ key: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "posture.\(key)").firstMatch
    }
}
