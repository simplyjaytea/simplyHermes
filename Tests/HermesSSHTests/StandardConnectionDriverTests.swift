import Foundation
import HermesKit
import Testing

@testable import HermesSSH

@Suite struct StandardConnectionDriverTests {
    /// A store whose Keychain refuses every read.
    private final class UnreadableStore: CredentialStore, @unchecked Sendable {
        func set(_ data: Data, for kind: CredentialKind, connection: UUID) throws {}
        func data(for kind: CredentialKind, connection: UUID) throws -> Data? {
            throw CredentialStoreError.keychain(status: -25308)
        }
        func remove(_ kind: CredentialKind, connection: UUID) throws {}
    }

    private struct NoSocketTransport: WebSocketTransport {
        func connect(url: URL, headers: [String: String]) async throws -> any WebSocketConnection {
            throw WebSocketError.failed("unused")
        }
    }

    @Test func aKeychainFailureFailsTheTunnelAndNamesTheKeychain() async throws {
        let driver = StandardConnectionDriver(
            credentials: UnreadableStore(), unlock: { _ in true }, makeWebSocket: { NoSocketTransport() })
        let settings = SSHSettings(host: "box.lan", port: 22, username: "jt")
        let connection = ServerConnection(name: "Box", kind: .ssh(settings))
        do {
            _ = try await driver.openTunnel(connection)
            Issue.record("expected a failure")
        } catch ConnectionTestFailure.ssh(let detail) {
            #expect(detail.contains("Keychain"))
        }
    }

    @Test func noSavedCredentialStillReachesTheMissingSecretCheck() async throws {
        let driver = StandardConnectionDriver(
            credentials: InMemoryCredentialStore(), unlock: { _ in true },
            makeWebSocket: { NoSocketTransport() })
        let settings = SSHSettings(host: "box.lan", port: 22, username: "jt")
        let connection = ServerConnection(name: "Box", kind: .ssh(settings))
        await #expect(throws: ConnectionTestFailure.missingSecret) { _ = try await driver.openTunnel(connection) }
    }
}
