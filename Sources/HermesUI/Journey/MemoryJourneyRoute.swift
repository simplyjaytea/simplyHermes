#if canImport(UIKit)
    import SwiftUI

    /// The `-HermesScreen memory` launch route (WP-52): the memory screen on its own, inside its own navigation stack.
    ///
    /// UI tests and screenshots use it to reach the screen without the Tools tab. It picks the layout the way the shell
    /// does: a forced layout (`-HermesLayout`) wins, otherwise the size class, the size and the posture decide.
    public struct MemoryJourneyRoute: View {
        private let connections: ConnectionsModel?
        private let layoutOverride: DisplayLayout?

        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
        @Environment(\.hermesPosture) private var posture

        /// `connections` supplies the active server. `layoutOverride` is the shell's forced layout, if there is one.
        public init(connections: ConnectionsModel?, layoutOverride: DisplayLayout?) {
            self.connections = connections
            self.layoutOverride = layoutOverride
        }

        public var body: some View {
            GeometryReader { proxy in
                let layout =
                    layoutOverride
                    ?? DisplayLayout.resolve(
                        horizontalSizeClass: horizontalSizeClass, size: proxy.size, posture: posture)
                NavigationStack { MemoryJourneyScreen(connections: connections) }
                    .environment(\.hermesDisplayLayout, layout)
            }
        }
    }
#endif
