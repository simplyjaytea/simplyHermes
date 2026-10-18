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
        /// Browser sign-in (WP-13).
        public var browserSignIn: any BrowserSigningIn
        /// Connects saved servers on demand (WP-15). Nil keeps everything offline (previews, snapshots).
        public var connectionDriver: (any ConnectionDriver)?

        public init(
            credentials: any CredentialStore,
            gatewayTester: any ConnectionTesting = GatewayConnectionTester(),
            sshTester: any ConnectionTesting = SSHConnectionTester(),
            unlocker: any DeviceUnlocking = SystemDeviceUnlocker(),
            probe: (@Sendable (HermesEndpoint) async -> ServerProbe?)? = nil,
            browserSignIn: any BrowserSigningIn = SystemBrowserSignIn(),
            connectionDriver: (any ConnectionDriver)? = nil, offline: Bool = false
        ) {
            self.credentials = credentials
            self.gatewayTester = gatewayTester
            self.sshTester = sshTester
            self.unlocker = unlocker
            self.probe = probe ?? { await GatewayConnectionTester().probe($0) }
            self.browserSignIn = browserSignIn
            self.connectionDriver =
                offline
                ? nil
                : connectionDriver
                    ?? StandardConnectionDriver(
                        credentials: credentials,
                        unlock: { [unlocker] connection in
                            await unlocker.unlock(reason: "Connect to \(connection.name)")
                        },
                        makeWebSocket: { URLSessionWebSocketTransport() })
        }
    }

    /// Saving failed.
    public enum ConnectionSaveError: Error, Equatable {
        /// Another saved connection reaches the same server.
        case duplicate(name: String)
        /// The Keychain or the file refused the write.
        case storage(String)
        /// The name is empty, too long or taken.
        case name(ConnectionNameProblem)

        public var message: String {
            switch self {
            case .duplicate(let name): "“\(name)” already connects to this server."
            case .name(let problem): problem.message
            case .storage(let detail): "Couldn't save the connection. \(detail)"
            }
        }
    }

    /// Saved servers, which one is active, and their secrets (WP-22).
    @MainActor
    @Observable
    public final class ConnectionsModel {
        public private(set) var saved: SavedConnections
        /// The live phase of each connection the manager has seen (WP-15).
        public private(set) var phases: [UUID: ConnectionPhase] = [:]
        @ObservationIgnored private let store: ConnectionStore?
        @ObservationIgnored public let services: ConnectionServices
        /// Connects on demand. Nil when ``ConnectionServices/connectionDriver`` is nil.
        @ObservationIgnored public private(set) var manager: ConnectionManager?
        /// False while a fleet update connects the saved servers, so those connects leave the last used server alone.
        @ObservationIgnored var recordsLastUsed = true
        @ObservationIgnored private var phaseWatcher: Task<Void, Never>?
        @ObservationIgnored private var fleetRun: FleetUpdateModel?

        /// The fleet update model, made on first use. The run lives here, not in the screen, so a reopened screen
        /// re-attaches to a run that goes on, and "Update all servers" cannot start a second run.
        public var fleetUpdate: FleetUpdateModel {
            if let fleetRun { return fleetRun }
            let model = FleetUpdateModel(connections: self)
            fleetRun = model
            return model
        }

        /// Loads saved connections from `store`. Nil keeps them in memory only (previews, UI tests).
        public init(store: ConnectionStore?, services: ConnectionServices, initial: SavedConnections? = nil) {
            self.store = store
            self.services = services
            saved = initial ?? (try? store?.load()) ?? SavedConnections()
            guard let driver = services.connectionDriver else { return }
            let manager = ConnectionManager(
                driver: driver,
                onConnected: { [weak self] id in Task { @MainActor in self?.markConnected(id) } })
            self.manager = manager
            phaseWatcher = Task { [weak self] in
                for await change in await manager.phaseChanges() {
                    self?.phases[change.id] = change.phase
                }
            }
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

        /// The primary connection: opened on launch unless ``openOnLaunch`` says Last used.
        public var primary: ServerConnection? { saved.primary }

        /// Makes a connection the primary one.
        public func setPrimary(_ id: UUID) {
            saved.setPrimary(id)
            persist()
        }

        /// Which connection opens after a restart.
        public var openOnLaunch: SavedConnections.OpenOnLaunch {
            get { saved.openOnLaunch }
            set {
                saved.openOnLaunch = newValue
                persist()
            }
        }

        /// The connection to open at launch.
        public var launchConnection: ServerConnection? { saved.launchConnection }

        /// At app start: makes the Open on launch connection the active one. It connects when a screen needs it.
        public func applyOpenOnLaunch() {
            guard let launch = saved.launchConnection, launch.id != saved.activeID else { return }
            saved.activeID = launch.id
            persist()
        }

        /// The live phase of a connection.
        public func phase(of id: UUID) -> ConnectionPhase { phases[id] ?? .idle }

        /// Starts connecting (connect on demand also happens when a screen asks the manager for a client).
        public func connect(_ id: UUID) {
            guard let connection = connection(id: id), let manager else { return }
            Task { await manager.connect(connection) }
        }

        /// Disconnects a connection. It connects again on demand.
        public func disconnect(_ id: UUID) {
            guard let manager else { return }
            Task { await manager.disconnect(id) }
        }

        private func markConnected(_ id: UUID) {
            guard recordsLastUsed else { return }
            saved.markConnected(id)
            persist()
        }

        /// Saves a new or edited connection and its secrets. Refuses a duplicate server.
        public func save(_ connection: ServerConnection, secrets: ConnectionSecrets) throws(ConnectionSaveError) {
            if let problem = saved.nameProblem(connection.name, for: connection.id) {
                throw .name(problem)
            }
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
            // An edit takes effect on the next connect.
            if let manager { Task { await manager.remove(connection.id) } }
            phases[connection.id] = nil
        }

        /// Deletes a connection and every secret it had.
        public func delete(_ id: UUID) {
            if let manager { Task { await manager.remove(id) } }
            phases[id] = nil
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
                sshPassword: try? credentials.string(for: .sshPassword, connection: id),
                nativeTokens: (try? credentials.data(for: .nativeTokens, connection: id))
                    .flatMap { try? JSONDecoder().decode(NativeTokens.self, from: $0) },
                webCookies: (try? credentials.data(for: .webCookies, connection: id))
                    .flatMap { try? JSONDecoder().decode([StoredCookie].self, from: $0) })
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
            func putJSON(_ value: (some Encodable)?, _ kind: CredentialKind) throws {
                if let value {
                    try credentials.set(try JSONEncoder().encode(value), for: kind, connection: id)
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
                var tokens: NativeTokens?
                var cookies: [StoredCookie]?
                if case .browser = settings.signIn {
                    tokens = secrets.nativeTokens
                    cookies = tokens == nil ? secrets.webCookies : nil
                }
                try putJSON(tokens, .nativeTokens)
                try putJSON(cookies, .webCookies)
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
                try credentials.remove(.nativeTokens, connection: id)
                try credentials.remove(.webCookies, connection: id)
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
                unlocker: AlwaysUnlocked(), probe: { _ in ServerProbe(authRequired: true, authProviders: ["basic"]) },
                browserSignIn: PreviewBrowserSignIn(), offline: true)
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

    /// A browser sign-in that succeeds at once. For previews.
    struct PreviewBrowserSignIn: BrowserSigningIn {
        @MainActor
        func signIn(
            endpoint: HermesEndpoint, options: SignInOptions?, provider: String?
        ) async throws -> BrowserSignInResult {
            .tokens(NativeTokens(accessToken: "a", refreshToken: "r", expiresAt: 0, provider: provider, userID: "jt"))
        }
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
