#if canImport(UIKit)
    import HermesKit
    import SwiftUI
    import UIKit

    /// The colours of the memory graph. System colours only, so light and dark mode and Increase Contrast come from the
    /// system. Slot 0 is for memory chunks, the other slots are shared out between skill categories.
    enum JourneyPalette {
        private static let colors: [Color] = [
            Color(uiColor: .systemGray),
            Color(uiColor: .systemBlue),
            Color(uiColor: .systemTeal),
            Color(uiColor: .systemGreen),
            Color(uiColor: .systemOrange),
            Color(uiColor: .systemPink),
            Color(uiColor: .systemPurple),
            Color(uiColor: .systemIndigo),
        ]

        /// The colour of a slot from `JourneyScene.Node.paletteIndex`. Out-of-range slots wrap around.
        static func color(slot: Int) -> Color {
            colors[((slot % colors.count) + colors.count) % colors.count]
        }

        /// The colour of a node: the same one in the list and in the graph.
        static func color(for node: JourneyNode) -> Color {
            color(slot: node.paletteIndex)
        }
    }
#endif
