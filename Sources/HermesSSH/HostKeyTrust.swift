@preconcurrency import Citadel
@preconcurrency import Crypto
import Foundation
import NIOCore
import NIOSSH

/// A server host key as shown to the user and stored with the connection.
public struct HostKeyInfo: Sendable, Equatable {
    /// OpenSSH public key line, e.g. `ssh-ed25519 AAAA…`. Store this to pin the key.
    public let openSSHKey: String
    /// OpenSSH-style fingerprint, e.g. `SHA256:47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU`.
    public let fingerprint: String

    public init(openSSHKey: String) throws {
        let parts = openSSHKey.split(separator: " ")
        guard parts.count >= 2, let blob = Data(base64Encoded: String(parts[1])) else {
            throw SSHTunnelError.unexpectedOutput("Malformed host key: \(openSSHKey)")
        }
        self.openSSHKey = "\(parts[0]) \(parts[1])"
        let digest = Data(SHA256.hash(data: blob)).base64EncodedString()
        self.fingerprint = "SHA256:" + digest.replacingOccurrences(of: "=", with: "")
    }
}

/// Host key policy. First connect is trust-on-first-use with an explicit user confirmation;
/// after that the stored key is pinned and a mismatch is a hard failure.
public enum HostKeyPolicy: Sendable {
    /// Ask the user to confirm the fingerprint. Return `true` to trust it.
    case trustOnFirstUse(confirm: @Sendable (HostKeyInfo) async -> Bool)
    /// Only accept this key (an OpenSSH public key line from ``HostKeyInfo/openSSHKey``).
    case pinned(openSSHKey: String)
}

/// Validates the server host key against a ``HostKeyPolicy`` and records the accepted key.
final class HostKeyValidator: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    private let policy: HostKeyPolicy
    private let lock = NSLock()
    private var _accepted: HostKeyInfo?
    private var _failure: SSHTunnelError?

    init(policy: HostKeyPolicy) {
        self.policy = policy
    }

    /// The key accepted during the handshake.
    var accepted: HostKeyInfo? { lock.withLock { _accepted } }
    /// Why validation failed, if it did. Citadel reports a generic error; this keeps the reason.
    var failure: SSHTunnelError? { lock.withLock { _failure } }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let info: HostKeyInfo
        do {
            info = try HostKeyInfo(openSSHKey: String(openSSHPublicKey: hostKey))
        } catch {
            fail(.unexpectedOutput("Unreadable host key"), validationCompletePromise)
            return
        }
        switch policy {
        case .pinned(let openSSHKey):
            guard let pinned = try? HostKeyInfo(openSSHKey: openSSHKey) else {
                fail(.invalidConfiguration("Stored host key is malformed"), validationCompletePromise)
                return
            }
            if pinned.openSSHKey == info.openSSHKey {
                accept(info, validationCompletePromise)
            } else {
                fail(
                    .hostKeyMismatch(expected: pinned.fingerprint, actual: info.fingerprint), validationCompletePromise)
            }
        case .trustOnFirstUse(let confirm):
            Task {
                if await confirm(info) {
                    self.accept(info, validationCompletePromise)
                } else {
                    self.fail(.hostKeyRejected(fingerprint: info.fingerprint), validationCompletePromise)
                }
            }
        }
    }

    private func accept(_ info: HostKeyInfo, _ promise: EventLoopPromise<Void>) {
        lock.withLock { _accepted = info }
        promise.succeed()
    }

    private func fail(_ error: SSHTunnelError, _ promise: EventLoopPromise<Void>) {
        lock.withLock { _failure = error }
        promise.fail(error)
    }
}
