import HermesUI
import SnapshotTesting
import SwiftUI
import XCTest

/// WP-20 gate: the component gallery in every Duo posture, light and dark, Reduce Motion on and off.
///
/// No one on the team has a Mac, so reference images are recorded on CI. A missing reference is
/// recorded and the test passes; an existing reference must match. Every rendered image is also
/// copied to `build/shots/gallery/` (uploaded with the CI screenshots) and attached to the test result.
@MainActor
final class ComponentGallerySnapshotTests: XCTestCase {
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    private static let referenceDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("__Snapshots__/ComponentGallery")
    private static let shotsDirectory = repoRoot.appendingPathComponent("build/shots/gallery")

    func testGalleryInEveryPosture() throws {
        for posture in DuoPreviewPosture.allCases {
            for style in [UIUserInterfaceStyle.light, .dark] {
                for reduceMotion in [false, true] {
                    let name = [
                        posture.rawValue,
                        style == .dark ? "dark" : "light",
                        reduceMotion ? "reducemotion" : "motion",
                    ].joined(separator: "-")
                    let view = ComponentGallery()
                        .environment(\.hermesReduceMotion, reduceMotion)
                        .frame(width: posture.size.width)
                        .fixedSize(horizontal: false, vertical: true)
                    try verifyRecordingMissing(AnyView(view), named: name, style: style)
                }
            }
        }
    }

    private func verifyRecordingMissing(_ view: AnyView, named name: String, style: UIUserInterfaceStyle) throws {
        // Drawn in the key window so Liquid Glass and materials render as on a device.
        let strategy = Snapshotting<AnyView, UIImage>.image(
            drawHierarchyInKeyWindow: true,
            perceptualPrecision: 0.98,
            layout: .sizeThatFits,
            traits: UITraitCollection(userInterfaceStyle: style)
        )
        let testName = "gallery"
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
