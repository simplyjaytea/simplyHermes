import HermesUI
import SnapshotTesting
import SwiftUI
import XCTest

/// WP-52 gate: the memory screen on the outer screen (list first) and the inner screens (graph first), in light and
/// dark, over the made-up sample graph.
///
/// References are recorded on CI like the gallery's: a missing reference is recorded and the test passes, an
/// existing one must match. Images are copied to `build/shots/journey/` for the CI screenshots artifact.
@MainActor
final class JourneySnapshotTests: XCTestCase {
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    private static let referenceDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("__Snapshots__/Journey")
    private static let shotsDirectory = repoRoot.appendingPathComponent("build/shots/journey")

    func testMemoryScreenInEveryPosture() throws {
        for posture in DuoPreviewPosture.allCases {
            for style in [UIUserInterfaceStyle.light, .dark] {
                let name = [posture.rawValue, style == .dark ? "dark" : "light"].joined(separator: "-")
                try verifyRecordingMissing(screen(for: posture), named: name, size: posture.size, style: style)
            }
        }
    }

    /// The screen as the shell shows it: the layout of the posture decides what comes first.
    private func screen(for posture: DuoPreviewPosture) -> AnyView {
        let layout: DisplayLayout
        switch posture {
        case .outer: layout = .compact
        case .innerPortrait: layout = .innerPortrait
        case .innerLandscape: layout = .innerLandscape
        case .halfFold: layout = .halfFold
        }
        return AnyView(
            NavigationStack { MemoryJourneyScreen(model: .sample()) }
                .environment(\.hermesDisplayLayout, layout))
    }

    private func verifyRecordingMissing(
        _ view: AnyView, named name: String, size: CGSize, style: UIUserInterfaceStyle
    ) throws {
        let strategy = Snapshotting<AnyView, UIImage>.image(
            drawHierarchyInKeyWindow: true,
            perceptualPrecision: 0.98,
            layout: .fixed(width: size.width, height: size.height),
            traits: UITraitCollection(userInterfaceStyle: style)
        )
        let testName = "journey"
        let reference = Self.referenceDirectory.appendingPathComponent("\(testName).\(name).png")
        let hadReference = FileManager.default.fileExists(atPath: reference.path)

        let failure = withSnapshotTesting(record: hadReference ? .never : .all) {
            verifySnapshot(
                of: view,
                as: strategy,
                named: name,
                snapshotDirectory: Self.referenceDirectory.path,
                testName: testName
            )
        }
        if hadReference, let failure {
            XCTFail(failure)
        }

        let image = try Data(contentsOf: reference)
        try FileManager.default.createDirectory(at: Self.shotsDirectory, withIntermediateDirectories: true)
        try image.write(to: Self.shotsDirectory.appendingPathComponent("\(name).png"))
        let attachment = XCTAttachment(data: image, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
