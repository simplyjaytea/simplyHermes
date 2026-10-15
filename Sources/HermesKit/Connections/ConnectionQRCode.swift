import Foundation

/// What a scanned QR code fills into the add-connection form.
///
/// Accepted forms:
/// - a gateway URL: `https://hermes.example.com/prefix`
/// - `simplyhermes://add?url=<gateway URL>&name=<name>&user=<basic user>`
/// - an SSH address: `ssh://user@host:port`
///
/// Codes never carry passwords or keys.
public enum ConnectionQRCode: Sendable, Equatable {
    /// A gateway to add.
    case gateway(url: String, name: String?, username: String?)
    /// An SSH host to add.
    case ssh(host: String, port: Int, username: String)

    /// Parses scanned text. Nil when it is none of the accepted forms.
    public init?(scanned text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed), let scheme = components.scheme?.lowercased()
        else { return nil }
        switch scheme {
        case "http", "https":
            guard components.host?.isEmpty == false else { return nil }
            self = .gateway(url: trimmed, name: nil, username: nil)
        case "simplyhermes":
            let items = components.queryItems ?? []
            func value(_ name: String) -> String? {
                items.first { $0.name == name }?.value.flatMap { $0.isEmpty ? nil : $0 }
            }
            guard components.host == "add", let url = value("url"), URLComponents(string: url)?.host != nil
            else { return nil }
            self = .gateway(url: url, name: value("name"), username: value("user"))
        case "ssh":
            guard let host = components.host, !host.isEmpty, let user = components.user, !user.isEmpty else {
                return nil
            }
            self = .ssh(host: host, port: components.port ?? 22, username: user)
        default:
            return nil
        }
    }
}
