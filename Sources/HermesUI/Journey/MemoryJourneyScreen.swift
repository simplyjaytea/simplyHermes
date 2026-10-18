#if canImport(UIKit)
    import SwiftUI

    /// Placeholder for the Memory journey (WP-52 replaces this file). It keeps the Tools tab's Memory row working until then.
    public struct MemoryJourneyScreen: View {
        public init() {}

        public var body: some View {
            ContentUnavailableView {
                Label("Memory journey", systemImage: "brain.head.profile")
            } description: {
                Text("The memory graph is coming soon.")
            }
            .navigationTitle("Memory")
        }
    }
#endif
