import HermesKit
import HermesUI
import SnapshotTesting
import SwiftUI
import XCTest

/// WP-63/64 gate: the Live Activity card, the expanded Dynamic Island and every Bots widget size,
/// in each turn state, light and dark.
///
/// Like the component gallery, references are recorded on CI: a missing reference is recorded and
/// the test passes. Every image is copied to `build/shots/live/` for the CI screenshot artifact.
@MainActor
final class LiveSurfacesSnapshotTests: XCTestCase {
    private static let referenceDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("__Snapshots__/LiveSurfaces")
    private static let shotsDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("build/shots/live")

    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private static let states: [(String, LiveTurnState)] = [
        (
            "thinking",
            LiveTurnState(
                phase: .thinking, botName: "Deploy bot", title: "Backup cron fix",
                lastLine: "Reading /etc/cron.d/backup and the last three nights of syslog",
                startedAt: now.addingTimeInterval(-74))
        ),
        (
            "tool",
            LiveTurnState(
                phase: .runningTool, botName: "Deploy bot", title: "Backup cron fix",
                lastLine: "grep backup /var/log/syslog", startedAt: now.addingTimeInterval(-131))
        ),
        (
            "approval",
            LiveTurnState(
                phase: .waitingForApproval, botName: "Deploy bot", title: "Backup cron fix",
                lastLine: "The NAS rejected the SSH key after its update.",
                pendingCommand: "ssh-copy-id backup@nas.local", startedAt: now.addingTimeInterval(-205))
        ),
        (
            "room",
            LiveTurnState(
                phase: .thinking, botName: "Release room", title: "Ship 0.2",
                lastLine: "Researcher: comparing changelogs", startedAt: now.addingTimeInterval(-640),
                activeBotCount: 3)
        ),
        (
            "done",
            LiveTurnState(
                phase: .done, botName: "Deploy bot", title: "Backup cron fix",
                lastLine: "Backup ran: 42 GB in 6 min", startedAt: now.addingTimeInterval(-400))
        ),
    ]

    func testLockScreenCard() throws {
        for (name, state) in Self.states {
            for style in [UIUserInterfaceStyle.light, .dark] {
                for isStale in [false, true] where !isStale || name == "thinking" {
                    let card = LiveTurnCard(state: state, isStale: isStale) {
                        LiveTurnButtonRow(state: state) { action in
                            Button(action.title) {}
                        }
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .frame(width: 370)
                    .padding(12)
                    .background(Color(white: style == .dark ? 0.1 : 0.75))
                    let suffix = isStale ? "-stale" : ""
                    try verify(AnyView(card), named: "card-\(name)\(suffix)-\(styleName(style))", style: style)
                }
            }
        }
    }

    func testExpandedIsland() throws {
        for (name, state) in Self.states {
            let island = LiveTurnIslandPreview(state: state) {
                HStack(spacing: 6) {
                    ForEach(LiveTurnAction.available(for: state), id: \.self) { action in
                        LiveTurnCompactButtonLabel(action)
                    }
                }
            }
            .frame(width: 370)
            .padding(12)
            .background(Color(white: 0.85))
            try verify(AnyView(island), named: "island-\(name)", style: .light)
        }
    }

    func testCompactIsland() throws {
        for (name, state) in Self.states {
            let compact = HStack {
                LiveTurnIslandLeading(state: state)
                Spacer()
                LiveTurnIslandTrailing(state: state)
            }
            .padding(.horizontal, 14)
            .frame(width: 250, height: 37)
            .foregroundStyle(.white)
            .background(.black, in: Capsule())
            .environment(\.colorScheme, .dark)
            .padding(8)
            try verify(AnyView(compact), named: "compact-\(name)", style: .light)
        }
    }

    func testBotsWidgets() throws {
        let snapshot = WidgetSnapshot.sample(now: Self.now)
        var quiet = snapshot
        quiet.approvals = []
        var stale = snapshot
        stale.updatedAt = Self.now.addingTimeInterval(-3600)
        let contents: [(String, BotsWidgetContent)] = [
            ("approval", .snapshot(snapshot)),
            ("quiet", .snapshot(quiet)),
            ("stale", .snapshot(stale)),
            ("unavailable", .unavailable),
        ]
        for (name, content) in contents {
            for style in [UIUserInterfaceStyle.light, .dark] {
                let suffix = "\(name)-\(styleName(style))"
                try verify(widget(content, size: .small, width: 170), named: "small-\(suffix)", style: style)
                try verify(widget(content, size: .medium, width: 364), named: "medium-\(suffix)", style: style)
            }
            let circular = BotsCircularWidgetView(content: content)
                .frame(width: 76, height: 76)
                .background(Color(white: 0.5).opacity(0.4), in: Circle())
                .padding(8)
            try verify(AnyView(circular), named: "circular-\(name)", style: .dark)
            let rectangular = BotsRectangularWidgetView(content: content)
                .frame(width: 172, height: 76)
                .padding(8)
            try verify(AnyView(rectangular), named: "rectangular-\(name)", style: .dark)
        }
    }

    private func widget(_ content: BotsWidgetContent, size: BotsWidgetSize, width: CGFloat) -> AnyView {
        AnyView(
            BotsWidgetView(content: content, size: size, now: Self.now) { _ in
                HStack(spacing: 6) {
                    LiveTurnCompactButtonLabel(.deny)
                    LiveTurnCompactButtonLabel(.approve)
                }
            }
            .padding(16)
            .frame(width: width, height: 170)
            .background(HermesColor.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(8)
        )
    }

    private func styleName(_ style: UIUserInterfaceStyle) -> String {
        style == .dark ? "dark" : "light"
    }

    private func verify(_ view: AnyView, named name: String, style: UIUserInterfaceStyle) throws {
        let strategy = Snapshotting<AnyView, UIImage>.image(
            drawHierarchyInKeyWindow: true,
            perceptualPrecision: 0.98,
            layout: .sizeThatFits,
            traits: UITraitCollection(userInterfaceStyle: style)
        )
        let frozen = AnyView(view.environment(\.hermesFrozenNow, Self.now))
        let testName = "live"
        let reference = Self.referenceDirectory.appendingPathComponent("\(testName).\(name).png")
        let hadReference = FileManager.default.fileExists(atPath: reference.path)

        let failure = withSnapshotTesting(record: hadReference ? .never : .all) {
            verifySnapshot(
                of: frozen,
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
