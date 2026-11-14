#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// A message the server does not have yet (WP-3). It sits after the transcript, as the user's own bubble, with its
    /// state under it. A message that failed shows its reason and what the user can do: Retry, Edit or Delete (WP-4).
    /// A status line under the transcript. It states what happened in plain words. It is never a reply and never a
    /// bubble (WP-4).
    struct StatusNote: View {
        @Environment(\.hermesPalette) private var palette
        let text: String

        var body: some View {
            Text(text)
                .font(HermesFont.footnote)
                .foregroundStyle(palette.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .accessibilityIdentifier("chat.statusNote")
        }
    }

    struct OutboxRow: View {
        @Environment(\.hermesPalette) private var palette
        let record: OutboundRecord
        let onRetry: () -> Void
        let onEdit: () -> Void
        let onDelete: () -> Void

        var body: some View {
            VStack(alignment: .trailing, spacing: 4) {
                MessageBubble(role: .user, text: record.text, rendersMarkdown: true)
                if case .failed(let reason) = record.state {
                    failedNote(reason)
                } else {
                    Text("Waiting to send")
                        .font(HermesFont.caption)
                        .foregroundStyle(palette.secondaryText)
                        .accessibilityIdentifier("outbox.state.\(record.id.uuidString)")
                }
            }
            .bubbleRow(.trailing)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("outbox.\(record.id.uuidString)")
        }

        private func failedNote(_ reason: String) -> some View {
            VStack(alignment: .trailing, spacing: 4) {
                Button(action: onRetry) {
                    Text("Not sent · Tap to retry")
                        .font(HermesFont.caption.weight(.semibold))
                        .foregroundStyle(palette.destructive)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("outbox.retry.\(record.id.uuidString)")
                Text(reason)
                    .font(HermesFont.caption2)
                    .foregroundStyle(palette.secondaryText)
                    .multilineTextAlignment(.trailing)
                HStack(spacing: 8) {
                    Button("Retry", action: onRetry)
                        .buttonStyle(HermesButtonStyle(.primary))
                    Button("Edit", action: onEdit)
                        .buttonStyle(HermesButtonStyle(.tinted))
                    Button("Delete", role: .destructive, action: onDelete)
                        .buttonStyle(HermesButtonStyle(.destructive))
                }
            }
        }
    }
#endif
