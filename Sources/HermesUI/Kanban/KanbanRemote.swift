#if canImport(UIKit)
    import Foundation
    import HermesKit

    /// Reaches the kanban API of the active server (WP-55). It connects on demand, as the chat list does.
    @MainActor
    enum KanbanRemote {
        /// The signed-in REST client of the active server. Throws ``ConnectionUnavailable`` when it cannot connect.
        static func rest(_ connections: ConnectionsModel) async throws -> RESTClient {
            guard let connection = connections.active, let manager = connections.manager else {
                throw ConnectionUnavailable(phase: .idle)
            }
            _ = try await manager.client(for: connection)
            guard let rest = await manager.rest(for: connection.id) else {
                throw ConnectionUnavailable(phase: await manager.phase(of: connection.id))
            }
            return rest
        }

        /// The sentence shown to the user when a kanban call fails.
        static func message(for error: any Error) -> String {
            switch error {
            case RESTError.http(_, let detail?): detail
            case RESTError.http(let status, nil): "The server answered \(status)."
            case RESTError.unauthorized: "Sign in again to use kanban."
            case RESTError.rateLimited: "The server is busy. Try again in a moment."
            case RESTError.transport: "Couldn't reach the server."
            case RESTError.unexpectedContent, RESTError.decoding: "The server sent an answer the app can't read."
            case is ConnectionUnavailable: "Couldn't connect to this server."
            default: "Something went wrong. Try again."
            }
        }
    }
#endif
