#if canImport(UIKit)
    import Foundation
    import HermesKit
    import HermesSSH
    import LocalAuthentication
    import Observation

    /// Asks for Face ID, Touch ID or the passcode.
    public protocol DeviceUnlocking: Sendable {
        /// True when the user proved who they are. `reason` is shown in the system prompt.
        func unlock(reason: String) async -> Bool
    }

    /// The system prompt (`deviceOwnerAuthentication`: biometrics with passcode fallback).
    public struct SystemDeviceUnlocker: DeviceUnlocking {
        public init() {}

        public func unlock(reason: String) async -> Bool {
            let context = LAContext()
            var error: NSError?
            // A phone with no passcode cannot gate anything; the Keychain item is still device-only.
            guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return true }
            return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
        }
    }

    /// Always unlocks. For previews, snapshots and UI tests.
    public struct AlwaysUnlocked: DeviceUnlocking {
        public init() {}
        public func unlock(reason: String) async -> Bool { true }
    }

    /// The services the connection screens use, so tests and previews can swap them.
    public struct ConnectionServices: Sendable {
        public var credentials: any CredentialStore
        public var gatewayTester: any ConnectionTesting
        public var sshTester: any ConnectionTesting
        public var unlocker: any DeviceUnlocking
        /// Reads a gateway's sign-in needs before the user signs in.
        public var probe: @Sendable (HermesEndpoint) async -> ServerProbe?

        public init(
            credentials: any CredentialStore,
            gatewayTester: any ConnectionTesting = GatewayConnectionTester(),
            sshTester: any ConnectionTesting = SSHConnectionTester(),
            unlocker: any DeviceUnlocking = SystemDeviceUnlocker(),
            probe: (@Sendable (HermesEndpoint) async -> ServerProbe?)? = nil
        ) {
            self.credentials = credentials
            self.gatewayTester = gatewayTester
            self.sshTester = sshTester
            self.unlocker = unlocker
            self.probe = probe ?? { await GatewayConnectionTester().probe($0) }
        }
    }

    /// Saving failed.
    public enum ConnectionSaveError: Error, Equatable {
        /// Another saved connection reaches the same server.
        case duplicate(name: String)
        /// The Keychain or the file refused the write.
        case storage(String)

        public var message: String {
            switch self {
            case .duplicate(let name): "“\(name)” already connects to this server."
            case .storage(let detail): "Couldn't save the connection. \(detail)"
            }
        }
    }

    /// Saved servers, which one is active, and their secrets (WP-22).
    @MainActor
    @Observable
    public final class ConnectionsModel {
        public private(set) var saved: SavedConnections
        @ObservationIgnored private let store: ConnectionStore?
        @ObservationIgnored public let services: ConnectionServices

        /// Loads saved connections from `store`. Nil keeps them in memory only (previews, UI tests).
        public init(store: ConnectionStore?, services: ConnectionServices, initial: SavedConnections? = nil) {
            self.store = store
            self.services = services
            saved = initial ?? (try? store?.load()) ?? SavedConnections()
        }

        public var connections: [ServerConnection] { saved.connections }
        public var active: ServerConnection? { saved.active }
        public var isEmpty: Bool { saved.connections.isEmpty }

        public func connection(id: UUID) -> ServerConnection? {
            saved.connections.first { $0.id == id }
        }

        /// Makes a connection the one the app uses.
        public func setActive(_ id: UUID) {
            guard connection(id: id) != nil else { return }
            saved.activeID = id
            persist()
        }

        /// Saves a new or edited connection and its secrets. Refuses a duplicate server.
        public func save(_ connection: ServerConnection, secrets: ConnectionSecrets) throws(ConnectionSaveError) {
            if let other = saved.duplicate(of: connection) {
                throw .duplicate(name: other.name)
            }
            do {
                try storeSecrets(secrets, for: connection)
            } catch {
                throw .storage("\(error)")
            }
            saved.upsert(connection)
            persist()
        }

        /// Deletes a connection and every secret it had.
        public func delete(_ id: UUID) {
            try? services.credentials.removeAll(connection: id)
            saved.remove(id: id)
            persist()
        }

        /// Reads a connection's secrets. Asks for Face ID first when the connection requires it.
        /// Nil when the user cancelled.
        public func secrets(for connection: ServerConnection, reason: String) async -> ConnectionSecrets? {
            if connection.requiresUnlock {
                guard await services.unlocker.unlock(reason: reason) else { return nil }
            }
            let credentials = services.credentials
            let id = connection.id
            return ConnectionSecrets(
                password: try? credentials.string(for: .gatewayPassword, connection: id),
                sessionToken: try? credentials.string(for: .sessionToken, connection: id),
                sshKey: try? credentials.sshKey(connection: id),
                sshPassword: try? credentials.string(for: .sshPassword, connection: id))
        }

        /// The tester for a connection's kind.
        public func tester(for connection: ServerConnection) -> any ConnectionTesting {
            connection.isSSH ? services.sshTester : services.gatewayTester
        }

        private func storeSecrets(_ secrets: ConnectionSecrets, for connection: ServerConnection) throws {
            let credentials = services.credentials
            let id = connection.id
            func put(_ value: String?, _ kind: CredentialKind) throws {
                if let value, !value.isEmpty {
                    try credentials.setString(value, for: kind, connection: id)
                } else {
                    try credentials.remove(kind, connection: id)
                }
            }
            switch connection.kind {
            case .gateway(let settings):
                var password: String?
                if case .password = settings.signIn, settings.remembersPassword { password = secrets.password }
                var token: String?
                if case .sessionToken = settings.signIn { token = secrets.sessionToken }
                try put(password, .gatewayPassword)
                try put(token, .sessionToken)
                try credentials.remove(.sshKey, connection: id)
                try credentials.remove(.sshPassword, connection: id)
            case .ssh(let settings):
                if settings.authentication == .password {
                    try put(secrets.sshPassword, .sshPassword)
                    try credentials.remove(.sshKey, connection: id)
                } else if let key = secrets.sshKey {
                    try credentials.setSSHKey(key, connection: id)
                    try credentials.remove(.sshPassword, connection: id)
                }
                try credentials.remove(.gatewayPassword, connection: id)
                try credentials.remove(.sessionToken, connection: id)
            }
        }

        private func persist() {
            try? store?.save(saved)
        }
    }

    extension ConnectionsModel {
        /// In-memory model for previews and snapshots. Tests always pass and never touch the network.
        public static func preview(_ connections: [ServerConnection]? = nil) -> ConnectionsModel {
            var saved = SavedConnections()
            for connection in connections ?? sampleConnections { saved.upsert(connection) }
            let services = ConnectionServices(
                credentials: InMemoryCredentialStore(), gatewayTester: PreviewTester(), sshTester: PreviewTester(),
                unlocker: AlwaysUnlocked(), probe: { _ in ServerProbe(authRequired: true, authProviders: ["basic"]) })
            return ConnectionsModel(store: nil, services: services, initial: saved)
        }

        public static let sampleConnections: [ServerConnection] = [
            ServerConnection(
                name: "Home server",
                kind: .gateway(
                    GatewaySettings(
                        endpoint: HermesEndpoint(string: "http://192.168.1.20:9119")!,
                        signIn: .password(username: "jt")))),
            ServerConnection(
                name: "Studio Mac", kind: .ssh(SSHSettings(host: "studio.tail1234.ts.net", username: "jt"))),
        ]
    }

    /// A tester that passes after a short pause. For previews.
    struct PreviewTester: ConnectionTesting {
        func test(
            _ connection: ServerConnection, secrets: ConnectionSecrets,
            progress: @escaping @Sendable (ConnectionTestStep) -> Void,
            confirmHostKey: @escaping @Sendable (HostKeyFingerprint) async -> Bool
        ) async throws -> ConnectionTestReport {
            progress(connection.isSSH ? .connectingSSH : .reachingServer)
            try await Task.sleep(for: .milliseconds(300))
            return ConnectionTestReport(
                serverVersion: "git.d97007c", releaseDate: "2026.9.24", signedInAs: "jt", authProviders: ["basic"])
        }
    }
#endif
