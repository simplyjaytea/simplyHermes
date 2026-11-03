import HermesKit
import HermesUI
import SnapshotTesting
import SwiftUI
import XCTest

/// WP-8 gate: every status pill state in every appearance preset (14 states x 4 presets = 56 images).
///
/// References are recorded on CI like the other snapshot suites: a missing reference is recorded and the test passes,
/// an existing one must match. Images are copied to `build/shots/pill/` for the CI screenshots artifact, and the
/// recorded references are then committed from that artifact.
@MainActor
final class PillSnapshotTests: XCTestCase {
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    private static let referenceDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("__Snapshots__/Pill")
    private static let shotsDirectory = repoRoot.appendingPathComponent("build/shots/pill")

    /// The 14 pill states: the 10 states of the pill itself, plus one for each of the four reasons an online chat
    /// needs the user.
    static let states: [(name: String, pill: PillState)] = [
        ("connected", .connected),
        ("connecting", .connecting),
        ("reconnecting", .reconnecting),
        ("unreachable", .unreachable),
        ("attention-signin", .needsAttention(.signIn)),
        ("attention-update", .needsAttention(.serverUpdate)),
        ("attention-hostkey", .needsAttention(.hostKey)),
        ("attention-settings", .needsAttention(.settings)),
        ("no-server", .noServer),
        ("local-ready", .localReady(.downloaded(id: "snapshot-model", displayName: "Snapshot Model"))),
        ("local-loading", .localLoading(.downloaded(id: "snapshot-model", displayName: "Snapshot Model"))),
        ("local-no-model", .localNoModel),
        (
            "local-failed",
            .localFailed(.downloaded(id: "snapshot-model", displayName: "Snapshot Model"), reason: .runtimeUnavailable)
        ),
        ("local-off", .localOff),
    ]

    func testEveryPillStateInEveryPreset() throws {
        XCTAssertEqual(Self.states.count, 14, "The matrix is 14 pill states")
        XCTAssertEqual(AppearancePreset.allCases.count, 4, "The matrix is 4 presets")
        for preset in AppearancePreset.allCases {
            for state in Self.states {
                let name = "\(state.name)-\(preset.id)"
                try verifyRecordingMissing(Self.view(state.pill, preset), named: name, size: Self.size)
            }
        }
    }

    private static let size = CGSize(width: 260, height: 60)

    /// The pill as the chat's header shows it, centred in a fixed frame so every reference has the same size.
    private static func view(_ pill: PillState, _ preset: AppearancePreset) -> AnyView {
        AnyView(
            StatusPill(pill: pill, serverName: "Home server")
                .frame(width: size.width, height: size.height)
                .environment(\.hermesAppearancePreset, preset))
    }

    private func verifyRecordingMissing(_ view: AnyView, named name: String, size: CGSize) throws {
        let strategy = Snapshotting<AnyView, UIImage>.image(
            drawHierarchyInKeyWindow: true,
            perceptualPrecision: 0.98,
            layout: .fixed(width: size.width, height: size.height),
            traits: UITraitCollection(userInterfaceStyle: .light)
        )
        let testName = "pill"
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
