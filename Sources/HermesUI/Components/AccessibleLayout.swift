#if canImport(UIKit)
    import SwiftUI

    /// A row that is an `HStack` at normal text sizes and a leading `VStack` at the accessibility sizes, so long text
    /// wraps instead of being squeezed or cut next to a button or a figure.
    struct AccessibleHStack<Content: View>: View {
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        private let spacing: CGFloat?
        private let content: Content

        init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
            self.spacing = spacing
            self.content = content()
        }

        var body: some View {
            let layout =
                dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
                : AnyLayout(HStackLayout(spacing: spacing))
            layout { content }
        }
    }

    extension View {
        /// For a symbol inside a fixed-size control, such as a round button: it grows with Dynamic Type up to
        /// accessibility size 1, then stops, so it never spills out of its circle.
        func cappedSymbolSize() -> some View {
            dynamicTypeSize(...DynamicTypeSize.accessibility1)
        }
    }

    /// Lines a one-line label may use: one at normal sizes, three at the accessibility sizes.
    struct AccessibleLineLimit: ViewModifier {
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        func body(content: Content) -> some View {
            content.lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
        }
    }

    extension View {
        /// One line, or up to three at the accessibility text sizes.
        func accessibleLineLimit() -> some View {
            modifier(AccessibleLineLimit())
        }
    }
#endif
