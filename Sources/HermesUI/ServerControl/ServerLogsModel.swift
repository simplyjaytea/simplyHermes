#if canImport(UIKit)
    import HermesKit
    import Observation

    /// The Logs screen (Tools > Logs): the server's log lines for a filter, and a stats header (WP-54).
    @MainActor
    @Observable
    public final class ServerLogsModel {
        /// The log lines, in the order the server sent them.
        public private(set) var lines: [String] = []
        /// The system stats header, a few rows.
        public private(set) var stats: [ServerStatsRow] = []
        public private(set) var isLoading = false
        /// Set when the read failed. The last lines stay on screen.
        public private(set) var errorText: String?

        @ObservationIgnored private let connections: ConnectionsModel

        public init(connections: ConnectionsModel) {
            self.connections = connections
        }

        /// Reads the lines for `filter` and the stats header.
        public func load(_ filter: ServerLogsFilter) async {
            guard connections.manager != nil else { return }
            guard let connection = connections.active, let backend = serverControlBackend(connections, connection)
            else {
                errorText = "Choose a server in Settings > Servers."
                return
            }
            isLoading = true
            defer { isLoading = false }
            do {
                let rest = try await backend.rest()
                if let system = try? await rest.systemStats() {
                    stats = Array(ServerStatsRows.rows(from: system).prefix(6))
                }
                let answer = try await rest.serverLogs(filter)
                lines = ServerLogsRows.lines(from: answer)
                errorText = nil
            } catch {
                errorText = ServerControlError.describe(error)
            }
        }

        /// Sample lines for previews.
        static let sampleLines: [String] = [
            "2026-10-18 09:12:04 INFO gateway: connected to telegram",
            "2026-10-18 09:14:31 WARNING agent: retrying the provider after a 429",
            "2026-10-18 09:15:02 ERROR tools: the terminal command timed out",
        ]

        /// A model with sample lines, for previews.
        static func preview(lines: [String], errorText: String? = nil) -> ServerLogsModel {
            let model = ServerLogsModel(connections: .preview())
            model.lines = lines
            model.errorText = errorText
            model.stats = [
                ServerStatsRow(label: "Cpu percent", value: "12.50"),
                ServerStatsRow(label: "Memory total mb", value: "4096"),
                ServerStatsRow(label: "Uptime s", value: "3600"),
            ]
            return model
        }
    }
#endif
