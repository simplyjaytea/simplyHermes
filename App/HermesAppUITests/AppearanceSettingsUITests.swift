#if canImport(XCTest)
    import XCTest

    /// End-to-end rendered UI tests for appearance preset selection, persistent storage across relaunch,
    /// and reset behavior in simplyHermes (plan WP-20).
    ///
    /// Requires macOS CI with an iOS Simulator runner.
    final class AppearanceSettingsUITests: XCTestCase {
        override func setUp() {
            continueAfterFailure = false
        }

        @MainActor
        func testAppearancePresetSelectionAndMarking() {
            let app = XCUIApplication()
            app.launchArguments += ["-HermesOnboarding", "skip"]
            app.launchArguments += ["-HermesLayout", "compact"]
            app.launch()

            navigateToAppearance(app)

            // Select Blue preset
            let blueButton = element(app, "appearance.preset.blue")
            XCTAssertTrue(blueButton.waitForExistence(timeout: 5))
            blueButton.tap()
            XCTAssertTrue(
                isSelected(blueButton),
                "Blue preset button should be marked as selected after tapping"
            )

            // Select Dark preset
            let darkButton = element(app, "appearance.preset.dark")
            XCTAssertTrue(darkButton.waitForExistence(timeout: 5))
            darkButton.tap()
            XCTAssertTrue(
                isSelected(darkButton),
                "Dark preset button should be marked as selected after tapping"
            )

            // Select White preset
            let whiteButton = element(app, "appearance.preset.white")
            XCTAssertTrue(whiteButton.waitForExistence(timeout: 5))
            whiteButton.tap()
            XCTAssertTrue(
                isSelected(whiteButton),
                "White preset button should be marked as selected after tapping"
            )

            // Reset to System
            let resetButton = element(app, "appearance.reset")
            XCTAssertTrue(resetButton.waitForExistence(timeout: 5))
            resetButton.tap()

            let systemButton = element(app, "appearance.preset.system")
            XCTAssertTrue(systemButton.waitForExistence(timeout: 5))
            XCTAssertTrue(
                isSelected(systemButton),
                "System preset button should be selected after resetting"
            )
        }

        @MainActor
        func testAppearancePresetPersistsAcrossRelaunch() {
            let app = XCUIApplication()
            app.launchArguments += ["-HermesOnboarding", "skip"]
            app.launchArguments += ["-HermesLayout", "compact"]
            app.launch()

            navigateToAppearance(app)

            // Select Blue preset
            let blueButton = element(app, "appearance.preset.blue")
            XCTAssertTrue(blueButton.waitForExistence(timeout: 5))
            blueButton.tap()
            XCTAssertTrue(isSelected(blueButton))

            // Relaunch the application
            app.terminate()
            app.launch()

            navigateToAppearance(app)

            // Verify Blue preset persisted
            let relaunchedBlue = element(app, "appearance.preset.blue")
            XCTAssertTrue(relaunchedBlue.waitForExistence(timeout: 5))
            XCTAssertTrue(
                isSelected(relaunchedBlue),
                "Blue preset should remain selected after app relaunch"
            )

            // Clean up: Reset to System
            let resetButton = element(app, "appearance.reset")
            if resetButton.waitForExistence(timeout: 5) {
                resetButton.tap()
            }
        }

        // MARK: - Navigation & Query Helpers

        @MainActor
        private func navigateToAppearance(_ app: XCUIApplication) {
            // If already on the Appearance screen, return immediately
            if app.navigationBars["Appearance"].exists {
                return
            }

            // Back out from default chat if needed
            if app.navigationBars["Backup cron fix"].exists {
                back(app, from: "Backup cron fix", to: "Chats")
            }

            guard let settingsTab = visibleTab(app, "Settings") else {
                XCTFail("Settings tab should be present in toolbar")
                return
            }
            settingsTab.tap()

            let appearanceRow = element(app, "settings.appearance")
            XCTAssertTrue(
                appearanceRow.waitForExistence(timeout: 5),
                "Settings > Appearance navigation link must exist"
            )
            appearanceRow.tap()

            XCTAssertTrue(
                app.navigationBars["Appearance"].waitForExistence(timeout: 5),
                "Appearance screen should be displayed"
            )
        }

        @MainActor
        private func isSelected(_ element: XCUIElement) -> Bool {
            if element.isSelected { return true }
            if let val = element.value as? String, val.contains("Selected") { return true }
            return false
        }

        @MainActor
        private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
            app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        }

        @MainActor
        private func back(_ app: XCUIApplication, from current: String, to previous: String) {
            let backButton = app.buttons["BackButton"]
            if backButton.waitForExistence(timeout: 3) {
                backButton.tap()
            }
            if !app.navigationBars[current].waitForNonExistence(timeout: 3) {
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
                let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
                start.press(forDuration: 0.1, thenDragTo: end)
            }
            XCTAssertTrue(
                app.navigationBars[current].waitForNonExistence(timeout: 5),
                "Expected to back out of \(current) to \(previous)"
            )
        }

        @MainActor
        private func visibleTab(_ app: XCUIApplication, _ title: String) -> XCUIElement? {
            let copies = app.buttons.matching(NSPredicate(format: "label == %@", title))
            let deadline = Date().addingTimeInterval(5)
            repeat {
                if let tab = copies.allElementsBoundByIndex.first(where: \.isHittable) {
                    return tab
                }
                Thread.sleep(forTimeInterval: 0.1)
            } while Date() < deadline
            return nil
        }
    }
#endif
