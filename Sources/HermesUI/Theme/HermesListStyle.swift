#if canImport(UIKit)
    import SwiftUI

    extension View {
        /// A List or Form on the preset's surfaces: the grouped background behind the rows and under the navigation bar.
        public func hermesThemedList() -> some View { modifier(HermesThemedList()) }
        /// The preset's card color behind list rows. Put it on a Section, or on a row outside a Section.
        public func hermesListRows() -> some View { modifier(HermesListRows()) }
    }

    private struct HermesThemedList: ViewModifier {
        @Environment(\.hermesPalette) private var palette

        func body(content: Content) -> some View {
            content
                .scrollContentBackground(.hidden)
                .background(palette.groupedBackground)
                .toolbarBackground(palette.groupedBackground, for: .navigationBar)
        }
    }

    private struct HermesListRows: ViewModifier {
        @Environment(\.hermesPalette) private var palette

        func body(content: Content) -> some View {
            content.listRowBackground(palette.card)
        }
    }
#endif
