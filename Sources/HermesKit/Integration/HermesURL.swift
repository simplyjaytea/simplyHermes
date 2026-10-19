import Foundation

/// The app's URL scheme, used by widgets and the Live Activity to open a chat
/// (Universal Links need a paid Apple account).
public enum HermesURL {
    public static let scheme = "simplyhermes"

    /// `simplyhermes://chat/<session id>`
    public static func chat(_ sessionID: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "chat"
        components.path = "/" + sessionID
        return components.url ?? URL(string: "\(scheme)://chat")!
    }

    /// The session ID in a chat URL, or `nil` for any other URL.
    public static func chatID(from url: URL) -> String? {
        guard url.scheme == scheme, url.host == "chat" else { return nil }
        let id = url.pathComponents.dropFirst().first ?? ""
        return id.isEmpty ? nil : id
    }

    /// `simplyhermes://session/<profile>/<session id>`: a session in one profile, opened from an `@session:` link (WP-40).
    public static func session(_ reference: SessionReference) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "session"
        components.path = "/" + reference.profile + "/" + reference.sessionID
        return components.url ?? URL(string: "\(scheme)://session")!
    }

    /// The profile and session in a session URL, or `nil` for any other URL.
    public static func sessionReference(from url: URL) -> SessionReference? {
        guard url.scheme == scheme, url.host == "session" else { return nil }
        let parts = url.pathComponents.dropFirst()
        guard parts.count == 2, let profile = parts.first, let sessionID = parts.last,
            SessionLink.isName(profile), SessionLink.isName(sessionID)
        else { return nil }
        return SessionReference(profile: profile, sessionID: sessionID)
    }
}
