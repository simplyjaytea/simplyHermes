import Foundation

/// A saved server: a gateway URL or an SSH host. Secrets (passwords, tokens, keys) never live here; they go to a
/// ``CredentialStore`` under ``id``.
public struct ServerConnection: Sendable, Hashable, Codable, Identifiable {
    /// Stable id. Also the Keychain account prefix for this connection's secrets.
    public var id: UUID
    /// Name shown in lists, for example "Home server".
    public var name: String
    /// How the app reaches the server.
    public var kind: Kind
    /// Ask for Face ID or the passcode before connecting. On by default for SSH (plan 2.4), off for gateways.
    public var requiresUnlock: Bool
    /// When the connection was added.
    public var createdAt: Date

    /// The two connection kinds of v1. Hermes Cloud comes later.
    public enum Kind: Sendable, Hashable, Codable {
        case gateway(GatewaySettings)
        case ssh(SSHSettings)
    }

    /// Creates a connection. `requiresUnlock` defaults to on for SSH and off for gateways.
    public init(
        id: UUID = UUID(), name: String, kind: Kind, requiresUnlock: Bool? = nil, createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.createdAt = createdAt
        if let requiresUnlock {
            self.requiresUnlock = requiresUnlock
        } else if case .ssh = kind {
            self.requiresUnlock = true
        } else {
            self.requiresUnlock = false
        }
    }

    /// Two connections with the same key reach the same server, so the app refuses to save a duplicate.
    ///
    /// Gateways compare by ``HermesEndpoint/normalizedKey``. SSH compares by normalized `user@host:port` plus the
    /// remote profile (plan 2.4).
    public var dedupeKey: String {
        switch kind {
        case .gateway(let settings):
            return "gateway " + settings.endpoint.normalizedKey
        case .ssh(let settings):
            let host = settings.host.trimmingCharacters(in: .whitespaces).lowercased()
            let profile = settings.remoteProfile?.trimmingCharacters(in: .whitespaces) ?? ""
            return "ssh \(settings.username)@\(host):\(settings.port) \(profile)"
        }
    }

    /// One line describing where the server is, for list rows: the URL, or `user@host:port`.
    public var address: String {
        switch kind {
        case .gateway(let settings):
            return settings.endpoint.baseURL.absoluteString
        case .ssh(let settings):
            let port = settings.port == 22 ? "" : ":\(settings.port)"
            return "\(settings.username)@\(settings.host)\(port)"
        }
    }

    /// True for SSH connections.
    public var isSSH: Bool {
        if case .ssh = kind { return true }
        return false
    }
}

/// A gateway connection: the dashboard server's URL and how to sign in.
public struct GatewaySettings: Sendable, Hashable, Codable {
    /// Base URL with an optional path prefix.
    public var endpoint: HermesEndpoint
    /// How the app signs in.
    public var signIn: GatewaySignIn
    /// Keep the password in the Keychain and sign in again silently when the server forgets the session
    /// (plan 2.3, opt-in).
    public var remembersPassword: Bool

    /// Creates gateway settings.
    public init(endpoint: HermesEndpoint, signIn: GatewaySignIn = .none, remembersPassword: Bool = false) {
        self.endpoint = endpoint
        self.signIn = signIn
        self.remembersPassword = remembersPassword
    }
}

/// How the app signs in to a gateway. Browser sign-in (PKCE, `WKWebView`) arrives with WP-13.
public enum GatewaySignIn: Sendable, Hashable, Codable {
    /// The server needs no login.
    case none
    /// The dashboard's `basic` provider. The password is in the ``CredentialStore``.
    case password(username: String)
    /// A pasted session token, stored in the ``CredentialStore``.
    case sessionToken
}

/// An SSH connection: where to log in and which key to use. The key itself is in the ``CredentialStore``.
public struct SSHSettings: Sendable, Hashable, Codable {
    /// Host name or IP address.
    public var host: String
    /// SSH port, 22 by default.
    public var port: Int
    /// Login user.
    public var username: String
    /// How the app authenticates.
    public var authentication: SSHAuthenticationKind
    /// The server's host key (`ssh-ed25519 AAAA…`) once the user trusted it. Nil until the first connect.
    public var pinnedHostKey: String?
    /// Custom `hermes` executable. Nil searches the usual places.
    public var hermesPath: String?
    /// Remote Hermes profile. Nil uses the server's active profile.
    public var remoteProfile: String?
    /// 32 lowercase hex characters, stable for this connection, so the app finds the dashboard it started.
    public var ownershipID: String

    /// Creates SSH settings. `ownershipID` defaults to a new random value.
    public init(
        host: String, port: Int = 22, username: String, authentication: SSHAuthenticationKind = .generatedKey,
        pinnedHostKey: String? = nil, hermesPath: String? = nil, remoteProfile: String? = nil,
        ownershipID: String? = nil
    ) {
        self.host = host
        self.port = port
        self.username = username
        self.authentication = authentication
        self.pinnedHostKey = pinnedHostKey
        self.hermesPath = hermesPath
        self.remoteProfile = remoteProfile
        self.ownershipID = ownershipID ?? Self.makeOwnershipID()
    }

    /// 32 random lowercase hex characters.
    public static func makeOwnershipID() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }
}

/// Which secret an SSH connection uses.
public enum SSHAuthenticationKind: String, Sendable, Hashable, Codable, CaseIterable {
    /// An Ed25519 key made on this phone.
    case generatedKey
    /// An OpenSSH private key file the user imported.
    case importedKey
    /// A password. Allowed, but keys are recommended.
    case password
}

/// A server host key as the user sees it: the key line to pin and its SHA256 fingerprint.
public struct HostKeyFingerprint: Sendable, Hashable {
    /// OpenSSH public key line, such as `ssh-ed25519 AAAA…`.
    public var openSSHKey: String
    /// `SHA256:…`, as `ssh-keygen -lf` prints it.
    public var fingerprint: String

    /// Creates a fingerprint value.
    public init(openSSHKey: String, fingerprint: String) {
        self.openSSHKey = openSSHKey
        self.fingerprint = fingerprint
    }
}
