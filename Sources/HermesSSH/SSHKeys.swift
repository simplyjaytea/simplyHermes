@preconcurrency import Citadel
@preconcurrency import Crypto
import Foundation
import NIOSSH
@preconcurrency import _CryptoExtras

/// How the app authenticates to the SSH server.
public enum SSHCredential: Sendable {
    case ed25519(Curve25519.Signing.PrivateKey)
    case rsa(Insecure.RSA.PrivateKey)
    case password(String)

    func authenticationMethod(username: String) -> SSHAuthenticationMethod {
        switch self {
        case .ed25519(let key): .ed25519(username: username, privateKey: key)
        case .rsa(let key): .rsa(username: username, privateKey: key)
        case .password(let password): .passwordBased(username: username, password: password)
        }
    }
}

/// Key generation, OpenSSH import and export. Keys are generated on device; the app stores
/// ``SSHKeys/rawRepresentation(of:)`` in the Keychain and shows ``SSHKeys/authorizedKeysLine(for:comment:)`` to the user.
public enum SSHKeys {
    /// A new Ed25519 key.
    public static func generateEd25519() -> Curve25519.Signing.PrivateKey {
        Curve25519.Signing.PrivateKey()
    }

    /// Parses an OpenSSH private key file (`-----BEGIN OPENSSH PRIVATE KEY-----`). Ed25519 and RSA are supported;
    /// `passphrase` decrypts an encrypted key.
    public static func importOpenSSHPrivateKey(_ text: String, passphrase: String? = nil) throws -> SSHCredential {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("-----BEGIN OPENSSH PRIVATE KEY-----") else {
            throw SSHTunnelError.invalidPrivateKey(
                "Not an OpenSSH private key. Convert it with ssh-keygen -p -f <key>.")
        }
        let decryptionKey = passphrase.flatMap { $0.isEmpty ? nil : Data($0.utf8) }
        do {
            return .ed25519(try Curve25519.Signing.PrivateKey(sshEd25519: trimmed, decryptionKey: decryptionKey))
        } catch {
            do {
                return .rsa(try Insecure.RSA.PrivateKey(sshRsa: trimmed, decryptionKey: decryptionKey))
            } catch {
                throw SSHTunnelError.invalidPrivateKey(
                    "Unsupported key type or wrong passphrase. Use an Ed25519 or RSA key.")
            }
        }
    }

    /// The `authorized_keys` line for a key: `ssh-ed25519 AAAA… comment`.
    public static func authorizedKeysLine(
        for key: Curve25519.Signing.PrivateKey, comment: String = "simplyHermes"
    ) -> String {
        let line = String(openSSHPublicKey: NIOSSHPrivateKey(ed25519Key: key).publicKey)
        return comment.isEmpty ? line : "\(line) \(comment)"
    }

    /// The key as an unencrypted OpenSSH private key file, for export.
    public static func openSSHPrivateKey(
        for key: Curve25519.Signing.PrivateKey, comment: String = "simplyHermes"
    ) -> String {
        key.makeSSHRepresentation(comment: comment)
    }

    /// The 32 raw private key bytes, for Keychain storage.
    public static func rawRepresentation(of key: Curve25519.Signing.PrivateKey) -> Data {
        key.rawRepresentation
    }

    /// Restores a key from ``rawRepresentation(of:)``.
    public static func ed25519(rawRepresentation data: Data) throws -> Curve25519.Signing.PrivateKey {
        try Curve25519.Signing.PrivateKey(rawRepresentation: data)
    }
}
