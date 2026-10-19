#if canImport(UIKit)
    import SwiftUI

    // The memory screen in every posture of the iPhone Duo, in light and dark, over the made-up sample graph (WP-52).

    /// The screen as the shell shows it for `layout`: the outer screen starts with the list, the others with the graph.
    @MainActor
    private func memoryPreview(_ layout: DisplayLayout) -> some View {
        NavigationStack { MemoryJourneyScreen(model: .sample()) }
            .environment(\.hermesDisplayLayout, layout)
    }

    #Preview("Outer, light", traits: .fixedLayout(width: 466, height: 678)) {
        memoryPreview(.compact).preferredColorScheme(.light)
    }

    #Preview("Outer, dark", traits: .fixedLayout(width: 466, height: 678)) {
        memoryPreview(.compact).preferredColorScheme(.dark)
    }

    #Preview("Inner portrait, light", traits: .fixedLayout(width: 626, height: 890)) {
        memoryPreview(.innerPortrait).preferredColorScheme(.light)
    }

    #Preview("Inner portrait, dark", traits: .fixedLayout(width: 626, height: 890)) {
        memoryPreview(.innerPortrait).preferredColorScheme(.dark)
    }

    #Preview("Inner landscape, light", traits: .fixedLayout(width: 890, height: 626)) {
        memoryPreview(.innerLandscape).preferredColorScheme(.light)
    }

    #Preview("Inner landscape, dark", traits: .fixedLayout(width: 890, height: 626)) {
        memoryPreview(.innerLandscape).preferredColorScheme(.dark)
    }

    #Preview("Half-fold, light", traits: .fixedLayout(width: 890, height: 313)) {
        memoryPreview(.halfFold).preferredColorScheme(.light)
    }

    #Preview("Half-fold, dark", traits: .fixedLayout(width: 890, height: 313)) {
        memoryPreview(.halfFold).preferredColorScheme(.dark)
    }
#endif
