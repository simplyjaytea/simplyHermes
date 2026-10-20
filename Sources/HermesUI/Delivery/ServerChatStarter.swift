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
            return try await NewServerChat.start(using: client, profile: chosen)
        }

        /// Waits for the connection, up to ``ConnectWait/patience``. A server only the user can fix ends the wait.
        private func connectedClient(
            of manager: ConnectionManager, for connection: ServerConnection
        ) async throws(NewChatFailure) -> GatewayClient {
            await manager.connect(connection)
            let began = Date()
            while !Task.isCancelled {
                let phase = await manager.phase(of: connection.id)
                switch ConnectWait.next(phase: phase, waited: Date().timeIntervalSince(began)) {
                case .proceed:
                    do {
                        return try await manager.client(for: connection)
                    } catch {
                        throw .notReachable
                    }
                case .giveUp:
                    throw .notReachable
                case .wait:
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
            throw .notReachable
        }
    }
#endif
