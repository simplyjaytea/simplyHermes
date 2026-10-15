import Crypto
import Foundation

/// An RFC 7636 PKCE pair plus the `state` for one native sign-in (RFC 8252).
public struct PKCEPair: Sendable, Equatable {
    /// The secret verifier: 43 base64url characters (32 random bytes). Sent only to `/auth/native/token`.
    public let verifier: String
    /// `base64url(sha256(verifier))` without padding. Sent to `/auth/native/authorize`.
    public let challenge: String
    /// Random value the server echoes back on the redirect. A mismatch rejects the callback.
    public let state: String

    /// The only method the server accepts.
    public static let method = "S256"

    /// Creates a pair from a known verifier and state, for tests.
    public init(verifier: String, state: String) {
        self.verifier = verifier
        self.challenge = Self.challenge(for: verifier)
        self.state = state
    }

    /// A fresh random pair.
    public static func generate() -> PKCEPair {
        var generator = SystemRandomNumberGenerator()
        return generate(using: &generator)
    }

    /// A pair from `generator`. Tests pass a seeded one.
    public static func generate(using generator: inout some RandomNumberGenerator) -> PKCEPair {
        PKCEPair(verifier: randomToken(bytes: 32, using: &generator), state: randomToken(bytes: 16, using: &generator))
    }

    /// The S256 challenge for `verifier`.
    public static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    /// `bytes` random bytes as base64url without padding.
    static func randomToken(bytes: Int, using generator: inout some RandomNumberGenerator) -> String {
        base64URL(Data((0..<bytes).map { _ in UInt8.random(in: .min ... .max, using: &generator) }))
    }

    /// Base64url without padding (RFC 4648 section 5).
    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
