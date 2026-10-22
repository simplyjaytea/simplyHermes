#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// Memory > Journey (WP-52): what Hermes has learned, as a list of nodes and as a graph over time.
    ///
    /// The screen goes inside the caller's `NavigationStack` (Tools > Memory, WP-51). The layout decides what comes
    /// first, the same way it does for the shell:
    /// - The outer screen (`DisplayLayout.compact`) starts with the node list, the filter chips and a Graph button that
    ///   pushes the graph.
    /// - The inner layouts (portrait, landscape and half-fold) start with the graph, and a List button pushes the list.
    ///
    /// Both views show the same model, so the filter, the timeline position and the open node carry over between them.
    /// A node opens in a sheet where it can be read, rewritten or deleted. The graph follows the active server and its
    /// profile: switching either loads that profile's graph.
    public struct MemoryJourneyScreen: View {
        @State private var model: MemoryJourneyModel
        private let connections: ConnectionsModel?
        private let attachesToConnections: Bool

        @Environment(\.hermesDisplayLayout) private var layout
        @Environment(\.scenePhase) private var scenePhase

        /// The screen for the active server of `connections`. With nil it shows "No server connected".
        public init(connections: ConnectionsModel? = nil) {
            _model = State(initialValue: MemoryJourneyModel())
            self.connections = connections
            attachesToConnections = true
        }

        /// The screen over a model that is ready made, for previews and snapshots. It never calls a server of its own.
        public init(model: MemoryJourneyModel) {
            _model = State(initialValue: model)
            connections = nil
            attachesToConnections = false
        }

        public var body: some View {
            root
                .task(id: connections?.active?.id) { await run() }
                .onChange(of: isActiveServerConnected) { _, connected in
                    if connected, case .failed = model.phase { Task { await model.refresh() } }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active, model.phase == .loaded { Task { await model.refresh() } }
                }
        }

        @ViewBuilder
        private var root: some View {
            if showsGraphFirst {
                JourneyGraphScreen(model: model, showsListButton: true)
            } else {
                JourneyListScreen(model: model, showsGraphButton: true)
            }
        }

        /// The inner layouts have the room for the graph. The outer screen, a plain iPhone and no layout at all start
        /// with the list.
        private var showsGraphFirst: Bool {
            guard let layout else { return false }
            switch layout {
            case .innerPortrait, .innerLandscape, .halfFold: return true
            case .compact, .tent: return false
            }
        }

        // MARK: Server

        /// Points the model at the active server, then watches for a switch of profile until the task is cancelled.
        private func run() async {
            guard attachesToConnections else { return }
            let source = makeSource()
            await model.attach(source)
            guard source != nil else { return }
            await model.watchProfile()
        }

        private func makeSource() -> JourneySource? {
            guard let connections, let manager = connections.manager, let active = connections.active else {
                return nil
            }
            let connectionID = active.id
            return JourneySource(
                id: connectionID.uuidString, name: active.name,
                backend: ManagedJourneyBackend(manager: manager, connection: active),
                currentProfile: { await manager.profile(of: connectionID) })
        }

        /// True while the active server is connected. A first load that failed because the server was down tries again
        /// when this turns true.
        private var isActiveServerConnected: Bool {
            guard let connections, let active = connections.active else { return false }
            if case .connected = connections.phase(of: active.id) { return true }
            return false
        }
    }
#endif
