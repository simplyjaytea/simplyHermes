#if canImport(XCTest)
    import HermesKit
    import XCTest

    /// End-to-end rendered UI tests for appearance preset selection, persistent storage across relaunch,
    /// reset behavior, and root environment palette propagation to production chat in simplyHermes (plan WP-20).
    ///
    /// Note on Multi-Window Testing:
    /// `HermesApp.swift` attaches `.hermesAppearance(activePreset)` to both `RootView` and secondary
    /// `WindowGroup(id: ShellWindow.chat)`. Secondary chat windows are supported on iPadOS and macOS multi-window
    /// configurations, but cannot be presented concurrently on single-window iPhone simulator test runners.
    /// Automated validation of view modifier propagation across independent view hierarchies is covered by
    /// `AppearancePresetAppTests.viewModifierActivelyPropagatesEnvironmentPalette`.
    ///
    /// Requires macOS CI with an iOS Simulator runner.
    final class AppearanceSettingsUITests: XCTestCase {
        override func setUp() {
            super.setUp()
            continueAfterFailure = false
        }

        override func tearDown() {
            super.tearDown()
        }

        @MainActor
        func testAppearancePresetSelectionAndRootPropagation() {
            let app = XCUIApplication()
            app.launchArguments += [
                "-HermesResetAppearance", "YES",
                "-HermesOnboarding", "skip",
                "-HermesLayout", "compact",
                "-HermesDebugLayoutSwitcher", "YES",
            ]
            app.launch()

            // Verify initial environment palette in chat starts as system
            XCTAssertEqual(
                activePreset(app),
                "system",
                "Chat environment should default to system preset"
            )

            navigateToAppearance(app)

            // Select Blue preset
            let blueButton = element(app, "appearance.preset.blue")
            XCTAssertTrue(blueButton.waitForExistence(timeout: 5))
            blueButton.tap()
            XCTAssertTrue(
                isSelected(blueButton),
                "Blue preset button should be marked as selected after tapping"
            )

            // Verify root propagation: Chat view inherits updated active preset
            navigateToChats(app)
            XCTAssertEqual(
                activePreset(app),
                "blue",
                "Root WindowGroup modifier should actively propagate 'blue' preset to Chat environment"
            )

            // Return to Appearance and select Dark preset
            navigateToAppearance(app)
            let darkButton = element(app, "appearance.preset.dark")
            XCTAssertTrue(darkButton.waitForExistence(timeout: 5))
            darkButton.tap()
            XCTAssertTrue(
                isSelected(darkButton),
                "Dark preset button should be marked as selected after tapping"
            )

            navigateToChats(app)
            XCTAssertEqual(
                activePreset(app),
                "dark",
                "Root WindowGroup modifier should actively propagate 'dark' preset to Chat environment"
            )

            // Return to Appearance and select White preset
            navigateToAppearance(app)
            let whiteButton = element(app, "appearance.preset.white")
            XCTAssertTrue(whiteButton.waitForExistence(timeout: 5))
            whiteButton.tap()
            XCTAssertTrue(
                isSelected(whiteButton),
                "White preset button should be marked as selected after tapping"
            )

            navigateToChats(app)
            XCTAssertEqual(
                activePreset(app),
                "white",
                "Root WindowGroup modifier should actively propagate 'white' preset to Chat environment"
            )

            // Reset to System: scroll down until reset button is hittable
            navigateToAppearance(app)
            let resetButton = element(app, "appearance.reset")
            scrollToElement(resetButton, in: app)
            XCTAssertTrue(resetButton.waitForExistence(timeout: 5))
            XCTAssertTrue(
                resetButton.isHittable,
                "Reset button should be visible and hittable before tapping"
            )
            resetButton.tap()

            let systemButton = element(app, "appearance.preset.system")
            XCTAssertTrue(systemButton.waitForExistence(timeout: 5))
            XCTAssertTrue(
                isSelected(systemButton),
                "System preset button should be selected after resetting"
            )

            navigateToChats(app)
            XCTAssertEqual(
                activePreset(app),
                "system",
                "Chat environment should revert to system after resetting appearance"
            )
        }

        @MainActor
        func testAppearancePresetPersistsAcrossRelaunch() {
            let app = XCUIApplication()
            app.launchArguments += [
                "-HermesResetAppearance", "YES",
                "-HermesOnboarding", "skip",
                "-HermesLayout", "compact",
                "-HermesDebugLayoutSwitcher", "YES",
            ]
            app.launch()

            XCTAssertEqual(activePreset(app), "system")

            navigateToAppearance(app)

            // Select Blue preset
            let blueButton = element(app, "appearance.preset.blue")
            XCTAssertTrue(blueButton.waitForExistence(timeout: 5))
            blueButton.tap()
            XCTAssertTrue(isSelected(blueButton))

            navigateToChats(app)
            XCTAssertEqual(activePreset(app), "blue")

            // Relaunch the application process without the reset appearance flag
            app.terminate()
            if let index = app.launchArguments.firstIndex(of: "-HermesResetAppearance") {
                app.launchArguments.remove(at: index)
                if index < app.launchArguments.count, app.launchArguments[index] == "YES" {
                    app.launchArguments.remove(at: index)
                }
            }
            app.launch()

            // Verify active preset in Chat immediately inherits stored Blue preset on fresh launch
            XCTAssertEqual(
                activePreset(app),
                "blue",
                "Blue preset should remain active in Chat environment across app relaunch"
            )

            navigateToAppearance(app)

            // Verify Blue preset remains selected in settings UI
            let relaunchedBlue = element(app, "appearance.preset.blue")
            XCTAssertTrue(relaunchedBlue.waitForExistence(timeout: 5))
            XCTAssertTrue(
                isSelected(relaunchedBlue),
                "Blue preset should remain selected in Appearance settings after app relaunch"
            )

            // Clean up: Reset to System
            let resetButton = element(app, "appearance.reset")
            scrollToElement(resetButton, in: app)
            if resetButton.waitForExistence(timeout: 5) {
                resetButton.tap()
            }

            navigateToChats(app)
            XCTAssertEqual(activePreset(app), "system")
        }

        // MARK: - Navigation & Query Helpers

        @MainActor
        private func activePreset(_ app: XCUIApplication) -> String {
            let label = element(app, "debug.activePreset")
            XCTAssertTrue(
                label.waitForExistence(timeout: 5),
                "debug.activePreset should exist in debug layout overlay"
            )
            return label.label
        }

        @MainActor
        private func navigateToChats(_ app: XCUIApplication) {
            if let chatsTab = visibleTab(app, "Chats") {
                chatsTab.tap()
            } else {
                let backButton = app.buttons["BackButton"]
                if backButton.waitForExistence(timeout: 2) {
                    backButton.tap()
                }
                if let chatsTab = visibleTab(app, "Chats") {
                    chatsTab.tap()
                }
            }
        }

        @MainActor
        private func navigateToAppearance(_ app: XCUIApplication) {
            // Back out from default chat if needed
            if app.navigationBars["Backup cron fix"].exists {
                back(app, from: "Backup cron fix", to: "Chats")
            }

            guard let settingsTab = visibleTab(app, "Settings") else {
                XCTFail("Settings tab should be present in toolbar")
                return
            }
            settingsTab.tap()

            if app.navigationBars["Appearance"].waitForExistence(timeout: 2) {
                return
            }

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
        private func scrollToElement(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 3) {
            var swipes = 0
            while !element.isHittable && swipes < maxSwipes {
                app.swipeUp()
                swipes += 1
            }
        }

        @MainActor
        private func isSelected(_ element: XCUIElement) -> Bool {
            if element.isSelected { return true }
            if let elementValue = element.value as? String, elementValue.contains("Selected") { return true }
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
