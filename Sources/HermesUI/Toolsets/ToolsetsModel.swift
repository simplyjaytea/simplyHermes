#if canImport(UIKit)
    import Foundation
    import HermesKit
    import Observation

    /// The toolsets of the active server, with their switches (WP-53b).
    ///
    /// A switch shows at once. The list is read again after the server answers. A switch that starts a background setup
    /// on the server names it in ``notice``; this screen does not follow that work.
    @MainActor
    @Observable
    public final class ToolsetsModel {
        public private(set) var toolsets: [ToolsetInfo] = []
        public private(set) var isLoading = false
        /// Set when the last read or switch failed. The list on screen stays.
        public private(set) var errorText: String?
        /// Set when a switch started a background setup on the server.
        public private(set) var notice: String?
        /// Switch values sent to the server and not answered yet, by toolset name.
        private var pending: [String: Bool] = [:]
        @ObservationIgnored private let connections: ConnectionsModel

        /// Creates a model. `toolsets` seeds the list, for previews.
        public init(connections: ConnectionsModel, toolsets: [ToolsetInfo] = []) {
            self.connections = connections
            self.toolsets = toolsets
        }

        /// Reads the list. Does nothing until a server is set up and connected.
        public func refresh() async {
            guard connections.active != nil, connections.manager != nil else { return }
            isLoading = true
            defer { isLoading = false }
            do {
                let rest = try await ToolsetAdminClient.rest(connections)
                toolsets = try await rest.toolsets()
                errorText = nil
            } catch is CancellationError {
                return
            } catch {
                errorText = ToolsetAdminClient.message(for: error)
            }
        }

        /// The switch to show: the value being sent, or else the stored one.
        public func isOn(_ toolset: ToolsetInfo) -> Bool {
            pending[toolset.name] ?? toolset.enabled
        }

        /// True while a switch of this toolset is being sent.
        public func isChanging(_ toolset: ToolsetInfo) -> Bool {
            pending[toolset.name] != nil
        }

        /// Switches a toolset on or off for the server's configuration platform, then reads the list again.
        public func setEnabled(_ toolset: ToolsetInfo, _ enabled: Bool) async {
            pending[toolset.name] = enabled
            defer { pending[toolset.name] = nil }
            do {
                let rest = try await ToolsetAdminClient.rest(connections)
                let result = try await rest.setToolsetEnabled(toolset.name, enabled: enabled)
                errorText = nil
                if result.postSetupStarted != nil {
                    let label = toolset.label ?? toolset.name
                    notice = "\(label) is setting up in the background. This screen doesn't follow its progress."
                }
            } catch is CancellationError {
                return
            } catch {
                errorText = ToolsetAdminClient.message(for: error)
            }
            await refresh()
        }
    }

    extension ToolsetsModel {
        /// A model with sample toolsets, for previews. It never reaches a server.
        static func preview() -> ToolsetsModel {
            ToolsetsModel(connections: .preview(), toolsets: ToolsetAdminSamples.toolsets)
        }
    }
#endif
