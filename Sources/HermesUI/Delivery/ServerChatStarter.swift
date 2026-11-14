#if canImport(UIKit)
    import Foundation
    import HermesKit

    /// Makes chats on the saved server for the ways into the app from outside: Siri and Shortcuts, Spotlight, the
    /// Share extension and Quick Entry.
    ///
    /// It goes the way the chat screens go. The connection connects on demand, and the chat is made under the chosen
    /// profile (bot). Showing the chat is left to the shell; its chat screen then connects it like any server chat.
    @MainActor
    public final class ServerChatStarter {
        private let connections: ConnectionsModel
        private let profiles: ProfilesModel

        public init(connections: ConnectionsModel) {
            self.connections = connections
            profiles = ProfilesModel(connections: connections)
        }

        /// Whether a server is saved. Without one there is nothing to make a chat on.
        public var hasServer: Bool { !connections.isEmpty }

        /// The name of the server a new chat is made on.
        public var serverName: String { connections.active?.name ?? "" }

        /// Connects if needed, then asks the server for a new chat.
        ///
        /// - Parameter profile: the bot to make the chat under. Nil uses the profile chosen in the app.
        public func start(profile: String? = nil) async throws(NewChatFailure) -> StartedChat {
            guard let connection = connections.active, let manager = connections.manager else { throw .notReachable }
            let client = try await connectedClient(of: manager, for: connection)
            var chosen = profile
            if chosen == nil {
                // Reads the remembered choice into the connection first, so a chat made right after launch is not
                // made under the default profile.
                await profiles.refresh()
                chosen = await manager.profile(of: connection.id)
            }
            let started = try await NewServerChat.start(using: client, profile: chosen)
            // The wait and the create can take 20 s and more. If the user changed servers meanwhile, this chat belongs
            // to a server that is no longer the active one: showing it would list it under the other server, and its
            // first message would be aimed there with this server's session id. The caller keeps the message as a
            // draft instead (the same check as ``NewChatStarter``).
            guard connections.active?.id == connection.id else { throw .notReachable }
            return started
        }

        /// Waits for the connection, up to ``ConnectWait/patience``. A server only the user can fix ends the wait.
        private func connectedClient(
            of manager: ConnectionManager, for connection: ServerConnection
        ) async throws(NewChatFailure) -> GatewayClient {
            let ready = await ConnectWait.connected(
                connect: { await manager.connect(connection) }, phase: { await manager.phase(of: connection.id) })
            guard ready else { throw .notReachable }
            do {
                return try await manager.client(for: connection)
            } catch {
                throw .notReachable
            }
        }
    }
#endif
