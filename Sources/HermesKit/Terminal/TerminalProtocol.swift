import Foundation

/// The byte contract of `/api/pty`. Read from the Hermes dashboard source; see docs/protocol.md section 13.
public enum TerminalProtocol {
    /// The terminal WebSocket path.
    public static let path = "/api/pty"

    /// The resize escape. The server reads it only when it is a whole frame, and never writes it to the PTY.
    public static func resizeFrame(columns: Int, rows: Int) -> Data {
        Data("\u{1B}[RESIZE:\(columns);\(rows)]".utf8)
    }

    /// The WebSocket URL for one terminal.
    ///
    /// `attach` names the PTY. A socket that connects with the same name reattaches to the PTY that is still running,
    /// so a tab keeps its shell while it is hidden. `profile` scopes the session the way REST does.
    public static func url(
        endpoint: HermesEndpoint, credential: GatewayCredential, attach: String, profile: String?
    ) -> URL {
        var target = "\(path)?attach=\(encode(attach))"
        if let profile, !profile.isEmpty { target += "&profile=\(encode(profile))" }
        switch credential {
        case .ticket(let ticket): return endpoint.webSocketURL(path: target, ticket: ticket)
        case .token(let token): return endpoint.webSocketURL(path: target, token: token)
        case .none: return endpoint.webSocketURL(path: target)
        }
    }

    /// Percent-encodes every character that is not a letter or digit, so a value never splits the query.
    private static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
    }
}
