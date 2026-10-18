#if canImport(UIKit)
    import SwiftUI

    /// The glass banner over the shell for an approval in a chat the user is not looking at (Q49).
    /// Approve answers it where it is; Open goes to the chat.
    struct ApprovalAlertBanner: View {
        let alert: ApprovalAlert
        let onApprove: () -> Void
        let onOpen: () -> Void

        var body: some View {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(alert.sessionTitle) needs approval")
                        .font(HermesFont.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(alert.command)
                        .font(HermesFont.footnote)
                        .foregroundStyle(HermesColor.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Button("Open", action: onOpen)
                    .buttonStyle(HermesButtonStyle(.tinted, fillsWidth: false))
                Button("Approve", action: onApprove)
                    .buttonStyle(HermesButtonStyle(.primary, fillsWidth: false))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("approvalAlert")
        }
    }

    /// Marks a chat that waits on an approval, on a sidebar row or a tab. Orange, so it differs from the blue streaming dot.
    struct ApprovalDot: View {
        var body: some View {
            Circle()
                .fill(HermesColor.statusWarning)
                .frame(width: 8, height: 8)
                .accessibilityLabel("Needs approval")
        }
    }
#endif
