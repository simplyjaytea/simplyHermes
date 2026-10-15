import HermesKit
import HermesUI
import SnapshotTesting
import SwiftUI
import XCTest

/// WP-22 gate: the connection screens on the outer and inner screens, light and dark.
///
/// References are recorded on CI like the gallery's: a missing reference is recorded and the test passes, an
/// existing one must match. Images are copied to `build/shots/connections/` for the CI screenshots artifact.
@MainActor
final class ConnectionSetupSnapshotTests: XCTestCase {
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    private static let referenceDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("__Snapshots__/ConnectionSetup")
    private static let shotsDirectory = repoRoot.appendingPathComponent("build/shots/connections")

    private static let screens: [(String, @MainActor () -> AnyView)] = [
        ("welcome", { AnyView(WelcomeView(connections: .preview([]))) }),
        ("gateway", { AnyView(ConnectionFormView(form: gatewayForm(), connections: .preview()) { _ in }) }),
        (
            "gateway-browser",
            { AnyView(ConnectionFormView(form: browserForm(), connections: .preview()) { _ in }) }
        ),
        ("ssh", { AnyView(ConnectionFormView(form: sshForm(), connections: .preview()) { _ in }) }),
        ("servers", { AnyView(NavigationStack { ServerListView(connections: .preview()) }) }),
        ("profile-switcher", { AnyView(profileSwitcherScreen()) }),
        (
            "hostkey",
            {
                AnyView(
                    HostKeyTrustSheet(
                        fingerprint: HostKeyFingerprint(
                            openSSHKey:
                                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl",
                            fingerprint: "SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU"),
                        onAnswer: { _ in }))
            }
        ),
    ]

    func testConnectionScreens() throws {
        for posture in [DuoPreviewPosture.outer, .innerPortrait] {
            for style in [UIUserInterfaceStyle.light, .dark] {
                for (screen, make) in Self.screens {
                    let name = [screen, posture.rawValue, style == .dark ? "dark" : "light"].joined(separator: "-")
                    try verifyRecordingMissing(make(), named: name, size: posture.size, style: style)
                }
            }
        }
    }

    private static func profileSwitcherScreen() -> some View {
        let json = #"""
            [{"name":"default","is_default":true},{"name":"ops","display_name":"Ops bot"},{"name":"research"}]
            """#
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let profiles = (try? decoder.decode([HermesProfile].self, from: Data(json.utf8))) ?? []
        let connections = ConnectionsModel.preview()
        let model = ProfilesModel.preview(ProfileSelection.resolve(profiles: profiles, stored: "ops"))
        return NavigationStack {
            Color.clear
                .navigationTitle("Chats")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        ProfileSwitcher(profiles: model, connections: connections)
                    }
                }
        }
    }

    private static func gatewayForm() -> ConnectionFormModel {
        let form = ConnectionFormModel(mode: .gateway)
        form.urlText = "http://192.168.1.20:9119"
        form.signInMethod = .password
        form.username = "jt"
        return form
    }

    /// WP-13: a gateway signed in through the browser.
    private static func browserForm() -> ConnectionFormModel {
        let connection = ServerConnection(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000013")!, name: "Office",
            kind: .gateway(
                GatewaySettings(
                    endpoint: HermesEndpoint(string: "https://hermes.example.com")!,
                    signIn: .browser(provider: "self-hosted"))),
            createdAt: Date(timeIntervalSince1970: 0))
        let tokens = NativeTokens(
            accessToken: "a", refreshToken: "r", expiresAt: 0, provider: "self-hosted", userID: "jt@example.com")
        return ConnectionFormModel(editing: connection, secrets: ConnectionSecrets(nativeTokens: tokens))
    }

    /// A fixed key, so the public key line is the same on every run.
    private static func sshForm() -> ConnectionFormModel {
        let connection = ServerConnection(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000022")!, name: "Studio Mac",
            kind: .ssh(
                SSHSettings(
                    host: "studio.tail1234.ts.net", username: "jt", ownershipID: String(repeating: "0", count: 32))),
            createdAt: Date(timeIntervalSince1970: 0))
        return ConnectionFormModel(
            editing: connection, secrets: ConnectionSecrets(sshKey: .ed25519(raw: Data(repeating: 7, count: 32))))
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
        let testName = "connections"
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
