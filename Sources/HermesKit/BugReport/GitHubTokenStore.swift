import Foundation

#if canImport(Security)
    import Security
#endif

/// Where the GitHub token for bug reports lives. The app uses ``KeychainGitHubTokenStore``.
public protocol GitHubTokenStore: Sendable {
    /// The saved token, or nil.
    func token() throws -> String?
    /// Saves or replaces the token.
    func setToken(_ token: String) throws
    /// Removes the token. Removing a missing token is not an error.
    func removeToken() throws
}

extension GitHubTokenStore {
    /// True when a non-empty token is saved. Keychain errors count as no token.
    public var hasToken: Bool { ((try? token()) ?? nil)?.isEmpty == false }
}

/// A token in memory. For tests and previews.
public final class InMemoryGitHubTokenStore: GitHubTokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    /// Creates a store, optionally with a token.
    public init(token: String? = nil) {
        value = token
    }

    public func token() throws -> String? { lock.withLock { value } }
    public func setToken(_ token: String) throws { lock.withLock { value = token } }
    public func removeToken() throws { lock.withLock { value = nil } }
}

/// Helpers for the token the user pastes.
public enum GitHubToken {
    /// Opens GitHub's new fine-grained token page with the name, owner and Issues permission filled in where GitHub
    /// supports it. The user still picks the simplyHermes repository and taps Generate.
    public static let createURL: URL = {
        var components = URLComponents(string: "https://github.com/settings/personal-access-tokens/new")!
        components.queryItems = [
            URLQueryItem(name: "name", value: "simplyHermes bug reports"),
            URLQueryItem(name: "description", value: "Files bug reports from the simplyHermes app"),
            URLQueryItem(name: "target_name", value: GitHubRepository.simplyHermes.owner),
            URLQueryItem(name: "expires_in", value: "none"),
            URLQueryItem(name: "issues", value: "write"),
        ]
        return components.url!
    }()

    /// Trims whitespace and newlines a paste can bring along. Nil when nothing is left.
    public static func cleaned(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

#if canImport(Security)
    /// The token as a Keychain generic password, on this device only and never synced
    /// (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, like the connection secrets).
    public struct KeychainGitHubTokenStore: GitHubTokenStore {
        private let service: String
        private let account = "bugReportToken"

        /// Creates a store.
        public init(service: String = "com.simplyjaytea.simplyhermes.github") {
            self.service = service
        }

        public func token() throws -> String? {
            var query = baseQuery
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecItemNotFound { return nil }
            guard status == errSecSuccess else { throw CredentialStoreError.keychain(status: status) }
            return (result as? Data).flatMap { String(bytes: $0, encoding: .utf8) }
        }

        public func setToken(_ token: String) throws {
            let attributes: [String: Any] = [
                kSecValueData as String: Data(token.utf8),
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ]
            var status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
            if status == errSecItemNotFound {
                status = SecItemAdd(baseQuery.merging(attributes) { _, new in new } as CFDictionary, nil)
            }
            guard status == errSecSuccess else { throw CredentialStoreError.keychain(status: status) }
        }

        public func removeToken() throws {
            let status = SecItemDelete(baseQuery as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw CredentialStoreError.keychain(status: status)
            }
        }

        private var baseQuery: [String: Any] {
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecAttrSynchronizable as String: false,
            ]
        }
    }
#endif
