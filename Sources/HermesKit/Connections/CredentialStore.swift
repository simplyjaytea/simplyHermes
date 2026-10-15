import Foundation

#if canImport(Security)
    import Security
#endif

/// The kinds of secret a connection can have.
public enum CredentialKind: String, Sendable, CaseIterable {
    /// Gateway `basic` password, kept only when the user turned on silent re-login.
    case gatewayPassword
    /// A pasted gateway session token.
    case sessionToken
    /// The SSH private key, as ``StoredSSHKey`` JSON.
    case sshKey
    /// The SSH password, for password login.
    case sshPassword
    /// Native sign-in tokens (access and rotating refresh token), as ``NativeTokens`` JSON.
    case nativeTokens
    /// Session cookies from the in-app web view sign-in, as ``StoredCookie`` JSON.
    case webCookies
}

/// Errors from a ``CredentialStore``.
public enum CredentialStoreError: Error, Sendable, Equatable {
    /// The Keychain refused the operation. `status` is the `OSStatus`.
    case keychain(status: Int32)
}

/// Where connection secrets live. The app uses ``KeychainCredentialStore``; tests use ``InMemoryCredentialStore``.
public protocol CredentialStore: Sendable {
    /// Saves or replaces a secret.
    func set(_ data: Data, for kind: CredentialKind, connection: UUID) throws
    /// Reads a secret. Nil when there is none.
    func data(for kind: CredentialKind, connection: UUID) throws -> Data?
    /// Removes one secret. Removing a missing secret is not an error.
    func remove(_ kind: CredentialKind, connection: UUID) throws
}

extension CredentialStore {
    /// Removes every secret of a connection, for delete.
    public func removeAll(connection: UUID) throws {
        for kind in CredentialKind.allCases { try remove(kind, connection: connection) }
    }

    /// Saves a string as UTF-8.
    public func setString(_ value: String, for kind: CredentialKind, connection: UUID) throws {
        try set(Data(value.utf8), for: kind, connection: connection)
    }

    /// Reads a UTF-8 string.
    public func string(for kind: CredentialKind, connection: UUID) throws -> String? {
        try data(for: kind, connection: connection).flatMap { String(bytes: $0, encoding: .utf8) }
    }

    /// Saves an SSH key.
    public func setSSHKey(_ key: StoredSSHKey, connection: UUID) throws {
        try set(try JSONEncoder().encode(key), for: .sshKey, connection: connection)
    }

    /// Reads an SSH key.
    public func sshKey(connection: UUID) throws -> StoredSSHKey? {
        guard let data = try data(for: .sshKey, connection: connection) else { return nil }
        return try JSONDecoder().decode(StoredSSHKey.self, from: data)
    }
}

/// An SSH private key as the app stores it.
public enum StoredSSHKey: Sendable, Hashable, Codable {
    /// The 32 raw bytes of an Ed25519 key made on the phone.
    case ed25519(raw: Data)
    /// An imported OpenSSH private key file and its passphrase, if it has one.
    case openSSH(text: String, passphrase: String?)
}

/// Secrets in memory. For tests, previews and the snapshot gallery.
public final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]

    /// Creates an empty store.
    public init() {}

    public func set(_ data: Data, for kind: CredentialKind, connection: UUID) throws {
        lock.withLock { items[Self.key(kind, connection)] = data }
    }

    public func data(for kind: CredentialKind, connection: UUID) throws -> Data? {
        lock.withLock { items[Self.key(kind, connection)] }
    }

    public func remove(_ kind: CredentialKind, connection: UUID) throws {
        _ = lock.withLock { items.removeValue(forKey: Self.key(kind, connection)) }
    }

    /// Number of stored secrets, for tests.
    public var count: Int { lock.withLock { items.count } }

    private static func key(_ kind: CredentialKind, _ connection: UUID) -> String {
        "\(connection.uuidString)/\(kind.rawValue)"
    }
}

#if canImport(Security)
    /// Secrets in the Keychain as generic passwords, readable after first unlock and never synced or backed up to
    /// another device (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, plan 2.4).
    ///
    /// `accessGroup` nil uses the app's default group. A sideloaded build is re-signed with another team prefix, so
    /// the shared group from WP-00 must be read at runtime before it is passed here.
    public struct KeychainCredentialStore: CredentialStore {
        /// The Keychain service name for every item.
        public let service: String
        /// The Keychain access group, or nil for the app's default.
        public let accessGroup: String?

        /// Creates a store.
        public init(service: String = "com.simplyjaytea.simplyhermes.connection", accessGroup: String? = nil) {
            self.service = service
            self.accessGroup = accessGroup
        }

        public func set(_ data: Data, for kind: CredentialKind, connection: UUID) throws {
            let query = baseQuery(kind, connection)
            let attributes: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ]
            var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if status == errSecItemNotFound {
                status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
            }
            guard status == errSecSuccess else { throw CredentialStoreError.keychain(status: status) }
        }

        public func data(for kind: CredentialKind, connection: UUID) throws -> Data? {
            var query = baseQuery(kind, connection)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecItemNotFound { return nil }
            guard status == errSecSuccess else { throw CredentialStoreError.keychain(status: status) }
            return result as? Data
        }

        public func remove(_ kind: CredentialKind, connection: UUID) throws {
            let status = SecItemDelete(baseQuery(kind, connection) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw CredentialStoreError.keychain(status: status)
            }
        }

        private func baseQuery(_ kind: CredentialKind, _ connection: UUID) -> [String: Any] {
            var query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: "\(connection.uuidString)/\(kind.rawValue)",
                kSecAttrSynchronizable as String: false,
            ]
            if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
            return query
        }
    }
#endif
