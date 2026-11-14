#if canImport(UIKit)
    import SwiftUI

    /// The glass banner over the shell for an approval in a chat the user is not looking at (Q49).
    /// Approve answers it where it is; Open goes to the chat.
    struct ApprovalAlertBanner: View {
        @Environment(\.hermesPalette) private var palette
        let alert: ApprovalAlert
        let onApprove: () -> Void
        let onOpen: () -> Void
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            // At the accessibility text sizes the buttons go below the text, full words on one line each: side by side
            // they were squeezed until "Approve" broke letter by letter and the title shrank to "Ba…" (iOS run
            // 43495829201, AccessibilitySizeUITests screenshots).
            AccessibleHStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(alert.sessionTitle) needs approval")
                        .font(HermesFont.subheadline.weight(.semibold))
                        .accessibleLineLimit()
                    Text(alert.command)
                        .font(HermesFont.footnote)
                        .foregroundStyle(palette.secondaryText)
                        .accessibleLineLimit()
                }
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 4) }
                HStack(spacing: 12) {
                    Button("Open", action: onOpen)
                        .buttonStyle(HermesButtonStyle(.tinted, fillsWidth: false))
                    Button("Approve", action: onApprove)
                        .buttonStyle(HermesButtonStyle(.primary, fillsWidth: false))
                }
                .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: HermesMetrics.bannerRadius, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("approvalAlert")
        }
    }

    /// Marks a chat that waits on an approval, on a sidebar row or a tab. Orange, so it differs from the blue streaming dot.
    struct ApprovalDot: View {
        @Environment(\.hermesPalette) private var palette
        var body: some View {
            Circle()
                .fill(palette.statusWarning)
                .frame(width: 8, height: 8)
                .accessibilityLabel("Needs approval")
        }
    }
#endif
