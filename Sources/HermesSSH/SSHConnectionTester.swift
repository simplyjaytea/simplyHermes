@preconcurrency import Crypto
import Foundation
import HermesKit

/// Key helpers for the SSH form: make a key, import one, show its `authorized_keys` line.
public enum SSHKeyMaterial {
    /// A new Ed25519 key, as stored, with its `authorized_keys` line.
    public static func generate(comment: String = "simplyHermes") -> (key: StoredSSHKey, publicLine: String) {
        let key = SSHKeys.generateEd25519()
        return (
            .ed25519(raw: SSHKeys.rawRepresentation(of: key)), SSHKeys.authorizedKeysLine(for: key, comment: comment)
        )
    }

    /// Checks an OpenSSH private key file and returns it as stored. Throws ``SSHTunnelError/invalidPrivateKey(_:)``
    /// with a message for the form.
    public static func importKey(_ text: String, passphrase: String?) throws -> StoredSSHKey {
        let stored = StoredSSHKey.openSSH(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            passphrase: passphrase.flatMap { $0.isEmpty ? nil : $0 })
        _ = try credential(for: stored)
        return stored
    }

    /// The `authorized_keys` line for an Ed25519 key. Nil for RSA keys and keys that do not parse.
    public static func publicLine(for stored: StoredSSHKey, comment: String = "simplyHermes") -> String? {
        guard case .ed25519(let key) = try? credential(for: stored) else { return nil }
        return SSHKeys.authorizedKeysLine(for: key, comment: comment)
    }

    /// The unencrypted OpenSSH private key file for a generated key, for export. Nil for imported keys.
    public static func privateKeyFile(for stored: StoredSSHKey, comment: String = "simplyHermes") -> String? {
        guard case .ed25519(let raw) = stored, let key = try? SSHKeys.ed25519(rawRepresentation: raw) else {
            return nil
        }
        return SSHKeys.openSSHPrivateKey(for: key, comment: comment)
    }

    /// The SSH credential for a stored key.
    public static func credential(for stored: StoredSSHKey) throws -> SSHCredential {
        switch stored {
        case .ed25519(let raw):
            do {
                return .ed25519(try SSHKeys.ed25519(rawRepresentation: raw))
            } catch {
                throw SSHTunnelError.invalidPrivateKey("The stored key is damaged. Generate a new one.")
            }
        case .openSSH(let text, let passphrase):
            return try SSHKeys.importOpenSSHPrivateKey(text, passphrase: passphrase)
        }
    }
}

/// Tests an SSH connection: log in, start Hermes on the server, open the tunnel, call `/api/status` through it,
/// then stop everything.
public struct SSHConnectionTester: ConnectionTesting {
    private let makeTransport: @Sendable () -> any HTTPTransport

    /// Creates a tester.
    public init(makeTransport: @escaping @Sendable () -> any HTTPTransport = { URLSessionHTTPTransport(timeout: 15) }) {
        self.makeTransport = makeTransport
    }

    public func test(
        _ connection: ServerConnection, secrets: ConnectionSecrets,
        progress: @escaping @Sendable (ConnectionTestStep) -> Void,
        confirmHostKey: @escaping @Sendable (HostKeyFingerprint) async -> Bool
    ) async throws -> ConnectionTestReport {
        guard case .ssh(let settings) = connection.kind else {
            throw ConnectionTestFailure.ssh("Not an SSH connection.")
        }
        let configuration = try Self.configuration(settings, secrets: secrets, confirmHostKey: confirmHostKey)
        let tunnel = SSHTunnel(configuration: configuration)
        let endpoint: SSHTunnelEndpoint
        do {
            endpoint = try await tunnel.start { step in
                switch step {
                case .connecting: progress(.connectingSSH)
                case .probing, .startingDashboard: progress(.startingDashboard)
                case .forwarding: progress(.forwarding)
                case .ready: break
                }
            }
        } catch {
            throw Self.failure(error)
        }

        progress(.checkingServer)
        let client = RESTClient(
            endpoint: endpoint.hermesEndpoint, transport: makeTransport(), auth: .sessionToken(endpoint.sessionToken))
        do {
            let health = try await client.health()
            let status = try? await client.status()
            await tunnel.stop()
            return ConnectionTestReport(
                serverVersion: health.displayVersion ?? endpoint.hermesVersion, releaseDate: status?.releaseDate,
                acceptedHostKey: HostKeyFingerprint(
                    openSSHKey: endpoint.hostKey.openSSHKey, fingerprint: endpoint.hostKey.fingerprint))
        } catch {
            await tunnel.stop()
            throw GatewayConnectionTester.reachFailure(error)
        }
    }

    /// The tunnel configuration for saved settings and secrets.
    public static func configuration(
        _ settings: SSHSettings, secrets: ConnectionSecrets,
        confirmHostKey: @escaping @Sendable (HostKeyFingerprint) async -> Bool
    ) throws -> SSHConfiguration {
        let credential: SSHCredential
        switch settings.authentication {
        case .generatedKey, .importedKey:
            guard let key = secrets.sshKey else { throw ConnectionTestFailure.missingSecret }
            do {
                credential = try SSHKeyMaterial.credential(for: key)
            } catch {
                throw failure(error)
            }
        case .password:
            guard let password = secrets.sshPassword, !password.isEmpty else {
                throw ConnectionTestFailure.missingSecret
            }
            credential = .password(password)
        }
        let hostKey: HostKeyPolicy =
            settings.pinnedHostKey.map { .pinned(openSSHKey: $0) }
            ?? .trustOnFirstUse { info in
                await confirmHostKey(HostKeyFingerprint(openSSHKey: info.openSSHKey, fingerprint: info.fingerprint))
            }
        return SSHConfiguration(
            host: settings.host.trimmingCharacters(in: .whitespaces), port: settings.port,
            username: settings.username, credential: credential, hostKey: hostKey,
            hermesPath: settings.hermesPath.flatMap { $0.isEmpty ? nil : $0 }, ownershipID: settings.ownershipID)
    }

    /// Maps tunnel errors to form messages.
    public static func failure(_ error: any Error) -> ConnectionTestFailure {
        switch error {
        case let failure as ConnectionTestFailure:
            return failure
        case SSHTunnelError.hostKeyMismatch(let expected, let actual):
            return .hostKeyChanged(expected: expected, actual: actual)
        case SSHTunnelError.hostKeyRejected:
            return .hostKeyRejected
        case SSHTunnelError.hermesNotFound:
            return .ssh("Logged in, but Hermes isn't installed on the server. Set the path to hermes under Advanced.")
        case SSHTunnelError.hermesTooOld(let version):
            return .ssh("Hermes \(version) on the server is too old. Update it with hermes update.")
        case SSHTunnelError.dashboardExited(let log):
            return .ssh("Hermes stopped while starting on the server. \(log.suffix(300))")
        case SSHTunnelError.dashboardStartTimedOut:
            return .ssh("Hermes took too long to start on the server.")
        case SSHTunnelError.invalidPrivateKey(let detail), SSHTunnelError.invalidConfiguration(let detail),
            SSHTunnelError.unexpectedOutput(let detail):
            return .ssh(detail)
        case SSHTunnelError.notConnected:
            return .ssh("The SSH connection closed.")
        default:
            return .unreachable(Self.describe(error))
        }
    }

    /// Citadel reports a refused login as a generic error; give it plain words.
    private static func describe(_ error: any Error) -> String {
        let text = "\(error)"
        if text.localizedCaseInsensitiveContains("authentication") || text.contains("allAuthenticationOptionsFailed") {
            return "The server refused the login. Add the public key to ~/.ssh/authorized_keys or check the password."
        }
        return text
    }
}
