import XCTest

/// WP-71 and WP-72: opens the chat in every layout, in light and dark, and at the largest text size, takes a
/// screenshot of each and runs Apple's accessibility audit.
///
/// The audit does not fail the run yet. It lists what it finds as an attachment, so the first CI results show how
/// much there is to fix; the test is meant to start failing on the audit kinds that are clean.
final class AccessibilityMatrixUITests: XCTestCase {
    private struct Variant {
        let layout: String
        let style: String
        let textSize: String?

        var name: String { "\(layout)-\(style)\(textSize == nil ? "" : "-largest-text")" }
    }

    private static let largestText = "UICTContentSizeCategoryAccessibilityXXXL"

    private static var variants: [Variant] {
        var result: [Variant] = []
        for layout in ["compact", "innerPortrait", "innerLandscape", "halfFold"] {
            for style in ["Light", "Dark"] {
                result.append(Variant(layout: layout, style: style, textSize: nil))
            }
        }
        result.append(Variant(layout: "compact", style: "Light", textSize: largestText))
        return result
    }

    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor
    func testChatInEveryLayoutAndStyle() throws {
        for variant in Self.variants {
            try XCTContext.runActivity(named: variant.name) { _ in
                try check(variant)
            }
        }
    }

    @MainActor
    private func check(_ variant: Variant) throws {
        let app = XCUIApplication()
        app.launchArguments += ["-HermesOnboarding", "skip", "-HermesLayout", variant.layout]
        app.launchArguments += ["-AppleInterfaceStyle", variant.style]
        if let size = variant.textSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", size]
        }
        app.launch()

        let transcript = app.descendants(matching: .any).matching(identifier: "transcript").firstMatch
        XCTAssertTrue(transcript.waitForExistence(timeout: 15), "\(variant.name): the chat should open")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = variant.name
        shot.lifetime = .keepAlways
        add(shot)

        var findings: [String] = []
        try app.performAccessibilityAudit { issue in
            let element = issue.element?.identifier ?? issue.element?.label ?? "unknown element"
            findings.append("\(issue.auditType.rawValue)\t\(element)\t\(issue.compactDescription)")
            return true
        }
        let report = XCTAttachment(string: findings.isEmpty ? "No findings" : findings.joined(separator: "\n"))
        report.name = "\(variant.name) audit"
        report.lifetime = .keepAlways
        add(report)
        print("AUDIT \(variant.name): \(findings.count) findings")
        for line in findings.prefix(40) { print("AUDIT \(variant.name): \(line)") }
        app.terminate()
    }
}
