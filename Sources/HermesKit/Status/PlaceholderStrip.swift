import Foundation

/// What the top strip of a New chat shows before its first message: the saved server the chat will start on, and
/// whether that server is connected now. A placeholder has no session yet, so it reads the server's connection, not a
/// chat's. It never invents a name or a state: with no server saved it says so.
public struct PlaceholderStrip: Sendable, Equatable {
    /// The saved server's name, or "No server".
    public var serverName: String
    /// The connection dot, from the same rules as a chat's pill.
    public var connection: StripConnection

    public init(serverName: String, connection: StripConnection) {
        self.serverName = serverName
        self.connection = connection
    }

    /// No server is saved, so the chat cannot start.
    public static let noServer = PlaceholderStrip(serverName: "No server", connection: .offline)

    /// The strip for a placeholder that will start on `server`, given that server's connection phase and the network.
    public static func derive(serverName: String, phase: ConnectionPhase?, path: NetworkPath) -> PlaceholderStrip {
        let status = ChatStatusDeriver.derive(
            backend: .server(connectionID: UUID(), profile: nil, sessionID: ""), phase: phase, path: path,
            local: .off)
        return PlaceholderStrip(serverName: serverName, connection: StripConnection(pill: status.pill))
    }
}
