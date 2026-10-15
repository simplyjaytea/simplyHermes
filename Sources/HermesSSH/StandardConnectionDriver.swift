import Foundation
import HermesKit

/// The app's ``ConnectionDriver`` (WP-15): Keychain secrets, SSH tunnels, and gateway sign-in through
/// ``GatewayAuthSession``.
public struct StandardConnectionDriver: ConnectionDriver {
    private let credentials: any CredentialStore
    private let unlocker: @Sendable (ServerConnection) async -> Bool
    private let makeTransport: @Sendable () -> any HTTPTransport
    private let makeWebSocket: @Sendable () -> any WebSocketTransport

    /// Creates the driver. `unlock` asks for Face ID; `makeWebSocket` opens gateway sockets.
    public init(
        credentials: any CredentialStore, unlock: @escaping @Sendable (ServerConnection) async -> Bool,
        makeTransport: @escaping @Sendable () -> any HTTPTransport = { URLSessionHTTPTransport() },
        makeWebSocket: @escaping @Sendable () -> any WebSocketTransport
    ) {
        self.credentials = credentials
        self.unlocker = unlock
        self.makeTransport = makeTransport
        self.makeWebSocket = makeWebSocket
    }

    public func unlock(_ connection: ServerConnection) async -> Bool {
        await unlocker(connection)
    }

    /// Opens the tunnel with the pinned host key. A connection that was never tested has no pinned key, so an
    /// unknown key is refused: the user trusts keys in the Test flow only.
    public func openTunnel(_ connection: ServerConnection) async throws -> OpenedTunnel {
        guard case .ssh(let settings) = connection.kind else {
            throw ConnectionTestFailure.ssh("Not an SSH connection.")
        }
        let secrets = ConnectionSecrets(
            sshKey: try? credentials.sshKey(connection: connection.id),
            sshPassword: try? credentials.string(for: .sshPassword, connection: connection.id))
        let configuration = try SSHConnectionTester.configuration(
            settings, secrets: secrets, confirmHostKey: { _ in false })
        let tunnel = SSHTunnel(configuration: configuration)
        do {
            let endpoint = try await tunnel.start()
            return OpenedTunnel(
                endpoint: endpoint.hermesEndpoint, sessionToken: endpoint.sessionToken, close: { await tunnel.stop() })
        } catch {
            await tunnel.stop()
            throw SSHConnectionTester.failure(error)
        }
    }

    public func checkServer(_ connection: ServerConnection, tunnel: OpenedTunnel?) async throws -> CheckedServer {
        switch connection.kind {
        case .gateway(let settings):
            let session = GatewayAuthSession(
                connectionID: connection.id, settings: settings, credentials: credentials, transport: makeTransport())
            return try await CheckedServer.gateway(session, endpoint: settings.endpoint)
        case .ssh:
            guard let tunnel else { throw ConnectionTestFailure.ssh("The tunnel is not open.") }
            return try await CheckedServer.tunnel(tunnel, transport: makeTransport())
        }
    }

    public func webSocketTransport(for connection: ServerConnection) -> any WebSocketTransport {
        makeWebSocket()
    }
}
