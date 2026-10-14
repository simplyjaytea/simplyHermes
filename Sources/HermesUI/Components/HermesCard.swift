#if canImport(UIKit)
    import SwiftUI

    /// A rounded card on the grouped background, for settings, bots and automations.
    public struct HermesCard<Content: View>: View {
        private let content: Content

        public init(@ViewBuilder content: () -> Content) {
            self.content = content()
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                HermesColor.card,
                in: RoundedRectangle(cornerRadius: HermesMetrics.cardRadius, style: .continuous)
            )
        }
    }

    /// Title row for a sheet, with a close button.
    public struct HermesSheetHeader: View {
        private let title: String
        private let onClose: () -> Void

        public init(_ title: String, onClose: @escaping () -> Void) {
            self.title = title
            self.onClose = onClose
        }

        public var body: some View {
            HStack {
                Text(title)
                    .font(HermesFont.headline)
                Spacer(minLength: 8)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(HermesColor.secondaryText)
                        .frame(width: HermesMetrics.minTapTarget, height: HermesMetrics.minTapTarget)
                        .background(HermesColor.fill, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close"))
            }
        }
    }

    extension View {
        /// A sheet with medium and large detents and a visible grabber.
        public func hermesSheet<Content: View>(
            isPresented: Binding<Bool>,
            @ViewBuilder content: @escaping () -> Content
        ) -> some View {
            sheet(isPresented: isPresented) {
                content()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }
#endif
