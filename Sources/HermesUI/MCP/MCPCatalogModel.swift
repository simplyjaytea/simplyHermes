#if canImport(UIKit)
    import Foundation
    import HermesKit
    import Observation

    /// The approved MCP catalog of the active server, and installs from it (WP-53b).
    ///
    /// An entry that needs a git clone and build runs that work in the background on the server. This model does not
    /// follow it, so the notice says so.
    @MainActor
    @Observable
    public final class MCPCatalogModel {
        public private(set) var entries: [MCPCatalogEntry] = []
        /// Entries the server could not load, one sentence each.
        public private(set) var diagnostics: [String] = []
        public private(set) var isLoading = false
        public private(set) var isInstalling = false
        /// Set when the last read failed. The list on screen stays.
        public private(set) var errorText: String?
        /// Set after an install: what the server started, and the note the entry gives after the install.
        public private(set) var notice: String?
        @ObservationIgnored private let connections: ConnectionsModel

        /// Creates a model. `catalog` seeds the lists, for previews.
        public init(connections: ConnectionsModel, catalog: MCPCatalog? = nil) {
            self.connections = connections
            if let catalog {
                apply(catalog)
            }
        }

        /// Reads the catalog. Does nothing until a server is set up and connected.
        public func refresh() async {
            guard connections.active != nil, connections.manager != nil else { return }
            isLoading = true
            defer { isLoading = false }
            do {
                let rest = try await ToolsetAdminClient.rest(connections)
                let catalog = try await rest.mcpCatalog()
                apply(catalog)
                errorText = nil
            } catch is CancellationError {
                return
            } catch {
                errorText = ToolsetAdminClient.message(for: error)
            }
        }

        /// Installs an entry with the values the user entered. Only the variables the entry declares are sent.
        /// Throws the server's answer when it refuses.
        public func install(_ entry: MCPCatalogEntry, env: [String: String]) async throws {
            let declared = Set((entry.requiredEnv ?? []).map(\.name))
            let values = env.filter { declared.contains($0.key) }
            isInstalling = true
            defer { isInstalling = false }
            let rest = try await ToolsetAdminClient.rest(connections)
            let result = try await rest.installMCPCatalogEntry(MCPCatalogInstall(name: entry.name, env: values))
            notice = Self.installNotice(for: entry, result: result)
            await refresh()
        }

        private func apply(_ catalog: MCPCatalog) {
            entries = catalog.entries
            diagnostics = (catalog.diagnostics ?? []).map(Self.sentence(for:))
        }

        private static func sentence(for diagnostic: MCPCatalogDiagnostic) -> String {
            let name = diagnostic.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let message = diagnostic.message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if name.isEmpty {
                return message.isEmpty ? "An entry could not be loaded." : message
            }
            return message.isEmpty ? "\(name) could not be loaded." : "\(name): \(message)"
        }

        private static func installNotice(for entry: MCPCatalogEntry, result: MCPCatalogInstallResult) -> String {
            var lines: [String] = []
            if result.background == true {
                lines.append(
                    "Installing \(entry.name) in the background. This screen doesn't follow its progress.")
            } else {
                lines.append("\(entry.name) is installed.")
            }
            if let note = entry.postInstall?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                lines.append(note)
            }
            return lines.joined(separator: "\n")
        }
    }

    extension MCPCatalogModel {
        /// A model with sample entries and one diagnostic, for previews. It never reaches a server.
        static func preview() -> MCPCatalogModel {
            MCPCatalogModel(connections: .preview(), catalog: ToolsetAdminSamples.catalog)
        }
    }
#endif
