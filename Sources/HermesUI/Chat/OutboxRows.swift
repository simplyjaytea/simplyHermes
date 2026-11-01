#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// A message the server does not have yet (WP-3). It sits after the transcript, as the user's own bubble, with its
    /// state under it. WP-4 adds the failed state and its actions.
    struct OutboxRow: View {
        let record: OutboundRecord

        var body: some View {
            VStack(alignment: .trailing, spacing: 2) {
                MessageBubble(role: .user, text: record.text, rendersMarkdown: true)
                Text("Waiting to send")
                    .font(HermesFont.caption)
                    .foregroundStyle(HermesColor.secondaryText)
                    .accessibilityIdentifier("outbox.state.\(record.id.uuidString)")
            }
            .bubbleRow(.trailing)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("outbox.\(record.id.uuidString)")
        }
    }
#endif
