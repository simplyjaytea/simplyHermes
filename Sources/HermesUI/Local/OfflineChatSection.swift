#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// The messages of an offline chat under an "Offline chat" header, in the same bubbles as a server chat (plan Q44).
    /// Use it wherever an offline chat is shown: below a server transcript, or in a screen of its own.
    public struct OfflineChatTranscript: View {
        private let messages: [OfflineChatMessage]
        private let isReplying: Bool
        private let failure: OfflineReplyFailure?

        public init(messages: [OfflineChatMessage], isReplying: Bool = false, failure: OfflineReplyFailure? = nil) {
            self.messages = messages
            self.isReplying = isReplying
            self.failure = failure
        }

        public var body: some View {
            VStack(spacing: HermesMetrics.bubbleSpacing) {
                Label("Offline chat", systemImage: "airplane")
                    .font(HermesFont.caption.weight(.semibold))
                    .foregroundStyle(HermesColor.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, HermesMetrics.bubbleHorizontalPadding)
                    .padding(.top, 8)
                    .accessibilityAddTraits(.isHeader)
                ForEach(messages) { message in
                    bubble(message)
                        .accessibilityIdentifier("offline.message.\(message.id)")
                }
                if isReplying {
                    TypingIndicator()
                }
                if let failure {
                    Text(Self.text(for: failure))
                        .font(HermesFont.caption)
                        .foregroundStyle(HermesColor.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, HermesMetrics.bubbleHorizontalPadding)
                        .accessibilityIdentifier("offline.failure")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("offline.chat")
        }

        @ViewBuilder
        private func bubble(_ message: OfflineChatMessage) -> some View {
            switch message.role {
            case .user:
                MessageBubble(role: .user, text: message.text, rendersMarkdown: true)
            case .assistant:
                StreamingText(text: message.text, isStreaming: false, rendersMarkdown: true)
            }
        }

        private static func text(for failure: OfflineReplyFailure) -> LocalizedStringKey {
            switch failure {
            case .unavailable: "The on-device model can't answer right now."
            case .modelFailed: "The on-device model couldn't answer. Try again."
            case .notSaved: "That message could not be saved."
            }
        }
    }

    /// The offline chat at the end of a server chat's transcript. It shows once the user has written offline, and
    /// goes away when the user answers the "Send to Hermes" offer. With `showsHint` it explains itself while empty.
    struct OfflineChatSection: View {
        let model: OfflineChatModel
        /// True when the server chat has nothing to show, so the offline notice fills the empty space.
        var showsHint = false

        var body: some View {
            if !model.messages.isEmpty || model.snapshot.isReplying || model.snapshot.failure != nil {
                OfflineChatTranscript(
                    messages: model.messages, isReplying: model.snapshot.isReplying, failure: model.snapshot.failure)
            } else if showsHint, model.notice == .offline {
                Text("You're offline. Messages you send now go to the model on this iPhone, not to Hermes.")
                    .font(HermesFont.footnote)
                    .foregroundStyle(HermesColor.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .accessibilityIdentifier("offline.hint")
            }
        }
    }
#endif
