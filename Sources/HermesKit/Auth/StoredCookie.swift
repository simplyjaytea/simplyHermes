import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// A cookie as the app stores it in the Keychain: the session cookies of a web view sign-in, so the sign-in
/// survives an app restart.
public struct StoredCookie: Sendable, Equatable, Codable {
    /// Cookie name.
    public var name: String
    /// Cookie value.
    public var value: String
    /// Domain, such as `hermes.example.com`.
    public var domain: String
    /// Path, such as `/`.
    public var path: String
    /// Expiry in Unix seconds. Nil for a browser-session cookie.
    public var expires: Double?
    /// Send only over HTTPS.
    public var secure: Bool

    /// Copies the fields of `cookie`.
    public init(_ cookie: HTTPCookie) {
        name = cookie.name
        value = cookie.value
        domain = cookie.domain
        path = cookie.path
        expires = cookie.expiresDate?.timeIntervalSince1970
        secure = cookie.isSecure
    }

    /// The cookie, or nil when the fields do not form one.
    public var cookie: HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name, .value: value, .domain: domain, .path: path,
        ]
        if let expires { properties[.expires] = Date(timeIntervalSince1970: expires) }
        if secure { properties[.secure] = "TRUE" }
        return HTTPCookie(properties: properties)
    }
}
