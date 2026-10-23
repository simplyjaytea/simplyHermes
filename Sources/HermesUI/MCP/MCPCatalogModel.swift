#if canImport(UIKit)
    import Foundation
    import HermesKit
    import Observation

    /// The approved MCP catalog of the active server, and installs from it (WP-53b).
    ///
    /// An install sends the values the user entered, then the catalog is read again. The server's answer is only
    /// checked for its status, so the notice says that this screen does not follow the install.
    @MainActor
    @Observable
    public final class MCPCatalogModel {
        public private(set) var entries: [MCPCatalogEntry] = []
        public private(set) var isLoading = false
        public private(set) var isInstalling = false
        /// Set when the last read failed. The list on screen stays.
        public private(set) var errorText: String?
        /// Set after an install the server accepted: one sentence, and the note the entry gives after the install.
        public private(set) var notice: String?
        @ObservationIgnored private let connections: ConnectionsModel

        /// Creates a model. `catalog` seeds the list, for previews.
        public init(connections: ConnectionsModel, catalog: MCPCatalog? = nil) {
            self.connections = connections
            if let catalog {
                entries = catalog.entries
            }
        }

        /// Reads the catalog. Does nothing until a server is set up and connected.
        public func refresh() async {
            guard connections.active != nil, connections.manager != nil else { return }
            isLoading = true
            defer { isLoading = false }
            do {
                let rest = try await ToolsetAdminClient.rest(connections)
                entries = try await rest.mcpCatalog().entries
                errorText = nil
            } catch is CancellationError {
                return
            } catch {
                errorText = ToolsetAdminClient.message(for: error)
            }
        }

        /// Installs an entry with the values the user entered. Only the variables the entry declares are sent.
        /// Throws the server's answer when it refuses. The catalog is read again after an accepted install.
        public func install(_ entry: MCPCatalogEntry, env: [String: String]) async throws {
            let declared = Set((entry.requiredEnv ?? []).map(\.name))
            let values = env.filter { declared.contains($0.key) }
            isInstalling = true
            defer { isInstalling = false }
            let rest = try await ToolsetAdminClient.rest(connections)
            try await rest.installMCPCatalogEntry(MCPCatalogInstall(name: entry.name, env: values))
            notice = Self.installNotice(for: entry)
            await refresh()
        }

        /// The sentence after an accepted install, with the entry's own note when it has one.
        private static func installNotice(for entry: MCPCatalogEntry) -> String {
            var lines = ["The server accepted the install of \(entry.name). This screen doesn't follow its progress."]
            if let note = entry.postInstall?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                lines.append(note)
            }
            return lines.joined(separator: "\n")
        }
    }

    extension MCPCatalogModel {
        /// A model with sample entries, for previews. It never reaches a server.
        static func preview() -> MCPCatalogModel {
            MCPCatalogModel(connections: .preview(), catalog: ToolsetAdminSamples.catalog)
        }
    }
#endif
