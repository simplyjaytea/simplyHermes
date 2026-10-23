#if canImport(UIKit)
    import Foundation
    import HermesKit

    /// Something the admin screens cannot do, apart from the server's own answers.
    public enum ToolsetAdminError: Error, Sendable, Equatable {
        /// No saved server is active.
        case noServer
    }

    /// The signed-in REST client of the active server, for the MCP and capability screens, and the sentences those
    /// screens show for errors (WP-53b).
    public enum ToolsetAdminClient {
        /// The client of the active server. Connects first when needed; throws when the server cannot be reached.
        @MainActor
        public static func rest(_ connections: ConnectionsModel) async throws -> RESTClient {
            guard let connection = connections.active, let manager = connections.manager else {
                throw ToolsetAdminError.noServer
            }
            _ = try await manager.client(for: connection)
            guard let rest = await manager.rest(for: connection.id) else {
                let phase = await manager.phase(of: connection.id)
                throw ConnectionUnavailable(phase: phase)
            }
            return rest
        }

        /// A sentence for the user. The server's own detail is kept when it sent one.
        public static func message(for error: any Error) -> String {
            if let rest = error as? RESTError {
                switch rest {
                case .unauthorized: return "Sign in to the server again."
                case .rateLimited: return "The server is busy. Try again in a moment."
                case .http(_, let detail): return detail ?? "The server refused the request."
                case .unexpectedContent: return "The server sent a web page instead of data. Check its address."
                case .transport: return "Can't reach the server."
                case .decoding: return "The server sent a reply this app doesn't understand."
                }
            }
            if error is ConnectionUnavailable { return "Can't reach the server right now." }
            if error is ToolsetAdminError { return "Add a server first." }
            return "Something went wrong. Try again."
        }
    }

    /// Sample answers for previews. They are decoded the way the app decodes the server's answers, so a preview never
    /// reaches a server. Secret values are never part of a sample.
    enum ToolsetAdminSamples {
        static var mcpServers: [MCPServerInfo] {
            decode(
                [MCPServerInfo].self,
                #"""
                [{"name":"github","transport":"stdio","command":"npx","enabled":true,"source":"config"},
                 {"name":"docs","transport":"http","enabled":false,"source":"config"}]
                """#) ?? []
        }

        static var catalog: MCPCatalog? {
            decode(
                MCPCatalog.self,
                #"""
                {"entries":[{"name":"github","description":"Issues, pull requests and code search.",
                  "transport":"stdio","auth_type":"none",
                  "required_env":[{"name":"GITHUB_TOKEN","prompt":"Personal access token","required":true}],
                  "installed":false,"enabled":false,"needs_install":false},
                 {"name":"notes","description":"Search your notes folder.","transport":"http",
                  "url":"https://notes.example/mcp","auth_type":"oauth","installed":true,"enabled":true,
                  "needs_install":true,"post_install":"Restart the Hermes session to use it."}]}
                """#)
        }

        static var computerUse: CapabilityComputerUseStatus? {
            decode(
                CapabilityComputerUseStatus.self,
                #"""
                {"platform":"darwin","platform_supported":true,"installed":true,"can_grant":true}
                """#)
        }

        /// Decodes a sample with the same key strategy as the client.
        static func decode<Value: Decodable>(_ type: Value.Type, _ json: String) -> Value? {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try? decoder.decode(type, from: Data(json.utf8))
        }
    }
#endif
