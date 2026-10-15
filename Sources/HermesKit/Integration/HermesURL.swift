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
}
