#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// What a New chat shows above its composer once it has a first message (board row 104): the outage banner when its
    /// own server cannot be reached, the message waiting to send, and the failed row if the server refused the chat.
    struct PlaceholderOutboxView: View {
        let model: ShellModel
        let queue: NewChatQueue
        let sessionID: String
        @Environment(\.hermesPalette) private var palette

        var body: some View {
            VStack(spacing: 8) {
                if OutageBanner.shows(queue.status(forRow: sessionID)), let name = queue.serverName(forRow: sessionID) {
                    OutageBannerView(
                        serverName: name,
                        onTryAgain: { queue.tryAgain(row: sessionID) },
                        onContinueInNewLocalChat: {
                            // Only the unsent draft goes to the Local chat. The waiting message stays with its server.
                            model.continueInNewLocalChat(carrying: model.drafts[sessionID, default: ""])
                        })
                }
                if let reason = queue.failures[sessionID] {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(reason)
                            .font(HermesFont.footnote)
                            .foregroundStyle(palette.secondaryText)
                        Button("Retry") { queue.retry(row: sessionID) }
                            .buttonStyle(HermesButtonStyle(.primary, fillsWidth: false))
                            .accessibilityIdentifier("newChat.retry")
                    }
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(queue.waiting[sessionID] ?? []) { record in
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(record.text)
                            .padding(10)
                            .background(palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        Text(record.state.kind == .failed ? "Not sent" : "Waiting to send")
                            .font(HermesFont.footnote)
                            .foregroundStyle(palette.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 12)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text("Waiting to send. \(record.text)"))
                }
            }
        }
    }
#endif
