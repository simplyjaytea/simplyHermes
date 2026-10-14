#if canImport(UIKit)
    import Foundation
    import HermesKit
    import HermesSSH
    import Observation

    /// The add or edit form for one connection: its fields, the Test button and host key trust (WP-22).
    @MainActor
    @Observable
    public final class ConnectionFormModel {
        public enum Mode: String, Sendable {
            case gateway
            case ssh
        }

        public enum SignInMethod: String, CaseIterable, Identifiable, Sendable {
            case none = "None"
            case password = "Password"
            case token = "Token"
            public var id: String { rawValue }
        }

        public enum KeySource: String, CaseIterable, Identifiable, Sendable {
            case generate = "Generate"
            case importKey = "Import"
            public var id: String { rawValue }
        }

        public enum TestState: Equatable, Sendable {
            case idle
            case running(ConnectionTestStep)
            case passed(ConnectionTestReport)
            case failed(ConnectionTestFailure)
        }

        public enum ProbeState: Equatable, Sendable {
            case idle
            case checking
            case found(ServerProbe)
            case unreachable
        }

        /// A host key waiting for the user's answer in the fingerprint sheet.
        public struct PendingTrust: Identifiable, Sendable {
            public let fingerprint: HostKeyFingerprint
            let continuation: CheckedContinuation<Bool, Never>
            public var id: String { fingerprint.fingerprint }
        }

        public let mode: Mode
        public let existingID: UUID?
        private let createdAt: Date

        public var name = ""
        public var requiresUnlock: Bool

        // Gateway
        public var urlText = ""
        public var signInMethod: SignInMethod = .none
        public var username = ""
        public var password = ""
        public var token = ""
        public var remembersPassword = false
        public private(set) var probe: ProbeState = .idle

        // SSH
        public var host = ""
        public var port = "22"
        public var sshUser = ""
        public var keySource: KeySource = .generate
        public private(set) var generatedKey: StoredSSHKey?
        public private(set) var publicKeyLine: String?
        public var importText = ""
        public var passphrase = ""
        public var hermesPath = ""
        public var remoteProfile = ""
        public private(set) var pinnedHostKey: String?
        private var ownershipID: String?

        public private(set) var test: TestState = .idle
        public var pendingTrust: PendingTrust?
        @ObservationIgnored private var autoTrustFingerprint: String?

        /// A blank form.
        public init(mode: Mode) {
            self.mode = mode
            existingID = nil
            createdAt = Date()
            requiresUnlock = mode == .ssh
            if mode == .ssh { generateKey() }
        }

        /// A form for an existing connection and its secrets.
        public init(editing connection: ServerConnection, secrets: ConnectionSecrets) {
            existingID = connection.id
            createdAt = connection.createdAt
            name = connection.name
            requiresUnlock = connection.requiresUnlock
            switch connection.kind {
            case .gateway(let settings):
                mode = .gateway
                urlText = settings.endpoint.baseURL.absoluteString
                remembersPassword = settings.remembersPassword
                switch settings.signIn {
                case .none: signInMethod = .none
                case .password(let user):
                    signInMethod = .password
                    username = user
                case .sessionToken: signInMethod = .token
                }
                password = secrets.password ?? ""
                token = secrets.sessionToken ?? ""
            case .ssh(let settings):
                mode = .ssh
                host = settings.host
                port = String(settings.port)
                sshUser = settings.username
                hermesPath = settings.hermesPath ?? ""
                remoteProfile = settings.remoteProfile ?? ""
                pinnedHostKey = settings.pinnedHostKey
                ownershipID = settings.ownershipID
                switch secrets.sshKey {
                case .ed25519(let raw)?:
                    keySource = .generate
                    generatedKey = .ed25519(raw: raw)
                    publicKeyLine = SSHKeyMaterial.publicLine(for: .ed25519(raw: raw))
                case .openSSH(let text, let phrase)?:
                    keySource = .importKey
                    importText = text
                    passphrase = phrase ?? ""
                case nil:
                    generateKey()
                }
            }
        }

        /// Fills the form from a scanned QR code.
        public convenience init(scanned code: ConnectionQRCode) {
            switch code {
            case .gateway(let url, let name, let user):
                self.init(mode: .gateway)
                urlText = url
                self.name = name ?? ""
                if let user {
                    signInMethod = .password
                    username = user
                }
            case .ssh(let host, let port, let user):
                self.init(mode: .ssh)
                self.host = host
                self.port = String(port)
                sshUser = user
            }
        }

        // MARK: Derived state

        /// The parsed gateway address, or why it is unusable. Nil while the field is empty.
        public var address: Result<ConnectionAddress.Parsed, ConnectionAddress.Problem>? {
            let parsed = ConnectionAddress.parse(urlText)
            if case .failure(.empty) = parsed { return nil }
            return parsed
        }

        /// The first thing missing, or nil when the form can be tested and saved.
        public var missing: String? {
            switch mode {
            case .gateway:
                guard case .success? = address else { return "Enter a valid server address." }
                switch signInMethod {
                case .none: return nil
                case .password: return username.isEmpty ? "Enter the user name." : nil
                case .token: return token.isEmpty ? "Paste the session token." : nil
                }
            case .ssh:
                if host.trimmingCharacters(in: .whitespaces).isEmpty { return "Enter the host." }
                if sshUser.isEmpty { return "Enter the user." }
                guard let portNumber = Int(port), (1...65535).contains(portNumber) else {
                    return "Enter a port from 1 to 65535."
                }
                if keySource == .importKey && importText.isEmpty { return "Paste the private key." }
                return nil
            }
        }

        public var isTesting: Bool {
            if case .running = test { return true }
            return false
        }

        // MARK: Actions

        /// Makes a new Ed25519 key and shows its `authorized_keys` line.
        public func generateKey() {
            let made = SSHKeyMaterial.generate()
            generatedKey = made.key
            publicKeyLine = made.publicLine
            pinnedHostKey = nil
            test = .idle
        }

        /// Reads the server's sign-in needs and picks a matching sign-in method.
        public func probeAddress(with services: ConnectionServices) async {
            guard mode == .gateway, case .success(let parsed)? = address else {
                probe = .idle
                return
            }
            probe = .checking
            guard let found = await services.probe(parsed.endpoint) else {
                probe = .unreachable
                return
            }
            guard !Task.isCancelled else { return }
            probe = .found(found)
            if !found.authRequired {
                signInMethod = .none
            } else if signInMethod == .none {
                signInMethod = found.authProviders.contains("basic") ? .password : .token
            }
        }

        /// The connection as typed. Throws a message for the form when a field is wrong.
        public func makeConnection() throws(ConnectionTestFailure) -> ServerConnection {
            if let missing { throw .invalidForm(missing) }
            let kind: ServerConnection.Kind
            switch mode {
            case .gateway:
                guard case .success(let parsed)? = address else { throw .invalidForm("Enter a valid server address.") }
                let signIn: GatewaySignIn =
                    switch signInMethod {
                    case .none: .none
                    case .password: .password(username: username)
                    case .token: .sessionToken
                    }
                kind = .gateway(
                    GatewaySettings(endpoint: parsed.endpoint, signIn: signIn, remembersPassword: remembersPassword))
            case .ssh:
                kind = .ssh(
                    SSHSettings(
                        host: host.trimmingCharacters(in: .whitespaces), port: Int(port) ?? 22, username: sshUser,
                        authentication: keySource == .generate ? .generatedKey : .importedKey,
                        pinnedHostKey: pinnedHostKey, hermesPath: hermesPath.isEmpty ? nil : hermesPath,
                        remoteProfile: remoteProfile.isEmpty ? nil : remoteProfile, ownershipID: ownershipID))
            }
            let fallbackName =
                switch mode {
                case .gateway: (try? address?.get())?.endpoint.baseURL.host() ?? "Server"
                case .ssh: host.trimmingCharacters(in: .whitespaces)
                }
            let trimmedName = name.trimmingCharacters(in: .whitespaces)
            return ServerConnection(
                id: existingID ?? UUID(), name: trimmedName.isEmpty ? fallbackName : trimmedName, kind: kind,
                requiresUnlock: requiresUnlock, createdAt: createdAt)
        }

        /// The secrets as typed. Imported keys are checked here.
        public func makeSecrets() throws(ConnectionTestFailure) -> ConnectionSecrets {
            switch mode {
            case .gateway:
                return ConnectionSecrets(
                    password: signInMethod == .password ? password : nil,
                    sessionToken: signInMethod == .token ? token : nil)
            case .ssh:
                switch keySource {
                case .generate:
                    return ConnectionSecrets(sshKey: generatedKey)
                case .importKey:
                    do {
                        return ConnectionSecrets(
                            sshKey: try SSHKeyMaterial.importKey(importText, passphrase: passphrase))
                    } catch {
                        throw SSHConnectionTester.failure(error)
                    }
                }
            }
        }

        /// Runs the connection test. SSH asks the user to trust the host key on first connect.
        public func runTest(with connections: ConnectionsModel) async {
            let connection: ServerConnection
            let secrets: ConnectionSecrets
            do throws(ConnectionTestFailure) {
                connection = try makeConnection()
                secrets = try makeSecrets()
            } catch {
                test = .failed(error)
                return
            }
            test = .running(mode == .ssh ? .connectingSSH : .reachingServer)
            do {
                let report = try await connections.tester(for: connection).test(
                    connection, secrets: secrets,
                    progress: { step in
                        Task { @MainActor in self.advance(to: step) }
                    },
                    confirmHostKey: { fingerprint in
                        await self.askToTrust(fingerprint)
                    })
                if let key = report.acceptedHostKey { pinnedHostKey = key.openSSHKey }
                test = .passed(report)
            } catch let failure as ConnectionTestFailure {
                test = .failed(failure)
            } catch {
                test = .failed(.unreachable("\(error)"))
            }
            autoTrustFingerprint = nil
        }

        /// The changed-key override: Face ID, then trust the new key and pin it.
        public func trustChangedKey(with connections: ConnectionsModel) async {
            guard case .failed(.hostKeyChanged(_, let actual)) = test else { return }
            guard await connections.services.unlocker.unlock(reason: "Trust the server's new key") else { return }
            autoTrustFingerprint = actual
            pinnedHostKey = nil
            await runTest(with: connections)
        }

        /// The answer from the fingerprint sheet.
        public func answerTrust(_ trusted: Bool) {
            pendingTrust?.continuation.resume(returning: trusted)
            pendingTrust = nil
        }

        /// Saves the connection. Returns the saved value, or throws a message for the form.
        @discardableResult
        public func save(to connections: ConnectionsModel) throws -> ServerConnection {
            let connection = try makeConnection()
            try connections.save(connection, secrets: try makeSecrets())
            return connection
        }

        private func advance(to step: ConnectionTestStep) {
            if case .running = test { test = .running(step) }
        }

        private func askToTrust(_ fingerprint: HostKeyFingerprint) async -> Bool {
            if fingerprint.fingerprint == autoTrustFingerprint { return true }
            pendingTrust?.continuation.resume(returning: false)
            return await withCheckedContinuation { continuation in
                pendingTrust = PendingTrust(fingerprint: fingerprint, continuation: continuation)
            }
        }
    }
#endif
