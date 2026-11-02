#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// A local chat: the saved messages, each reply labelled with the model that wrote it, and a composer. Nothing on
    /// this screen reaches a server.
    public struct LocalChatScreen: View {
        @Bindable var model: LocalChatModel
        @State private var draft = ""
        @Environment(\.hermesPalette) private var palette

        public init(model: LocalChatModel) {
            self.model = model
        }

        public var body: some View {
            VStack(spacing: 0) {
                transcript
                if model.snapshot.needsReply {
                    noReplyRow
                } else if let note = failureNote {
                    Text(note)
                        .font(HermesFont.footnote)
                        .foregroundStyle(palette.errorText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .accessibilityIdentifier("local.failure")
                }
                Composer(text: $draft) { submit() }
                    .background(palette.background)
            }
            .background(palette.background)
            .onDisappear { model.stop() }
        }

        /// The newest message has no reply: it failed, or the app stopped before one came. Retry asks again.
        private var noReplyRow: some View {
            HStack {
                Text(failureNote ?? "No reply to this message.")
                    .font(HermesFont.footnote)
                    .foregroundStyle(palette.errorText)
                    .accessibilityIdentifier("local.failure")
                Spacer()
                Button("Retry") { model.retry() }
                    .buttonStyle(HermesButtonStyle(.primary, fillsWidth: false))
                    .accessibilityIdentifier("local.retry")
            }
            .padding(.horizontal)
        }

        private var transcript: some View {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if model.snapshot.messages.isEmpty {
                        Text("Answered on this iPhone. Nothing here is sent to Hermes.")
                            .font(HermesFont.footnote)
                            .foregroundStyle(palette.secondaryText)
                            .accessibilityIdentifier("local.empty")
                    }
                    ForEach(model.snapshot.messages) { message in
                        row(message)
                    }
                    if model.snapshot.isReplying {
                        ProgressView()
                            .accessibilityLabel("Reply in progress")
                            .accessibilityIdentifier("local.replying")
                    }
                }
                .padding()
            }
            .defaultScrollAnchor(.bottom)
            .accessibilityIdentifier("local.transcript")
        }

        @ViewBuilder
        private func row(_ message: LocalChatMessage) -> some View {
            switch message.author {
            case .user:
                HStack {
                    Spacer(minLength: 40)
                    Text(message.text)
                        .textSelection(.enabled)
                        .padding(12)
                        .background(palette.outgoingBubble, in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityIdentifier("local.message.user")
                }
            case .assistant(let identity):
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.text)
                        .textSelection(.enabled)
                        .padding(12)
                        .background(palette.incomingBubble, in: RoundedRectangle(cornerRadius: 16))
                    Label(Self.answeredBy(identity), systemImage: "iphone")
                        .font(HermesFont.caption)
                        .foregroundStyle(palette.secondaryText)
                        .accessibilityIdentifier("local.message.model")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        /// "On this iPhone · {model}". A reply saved before models were recorded names only the device.
        static func answeredBy(_ identity: ModelIdentity?) -> String {
            guard let identity else { return "On this iPhone" }
            return "On this iPhone · \(identity.displayName)"
        }

        private var failureNote: String? {
            switch model.snapshot.failure {
            case nil: nil
            case .unavailable(.switchedOff): "On-device features are off. Turn them on in Settings to get a reply."
            case .unavailable(.disabled): "Turn on Apple Intelligence in Settings to get a reply here."
            case .unavailable(.notReady): "The on-device model is not ready yet. Try again in a moment."
            case .unavailable(.unsupported): "This iPhone cannot answer here."
            case .modelFailed: "No reply: the on-device model did not answer."
            case .notSaved: "This message could not be saved on this iPhone."
            }
        }

        private func submit() {
            let text = draft
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            Task {
                // The composer clears only once the message is saved, so a failed save keeps the text.
                if await model.submit(text), draft == text { draft = "" }
            }
        }
    }

    /// The badge that marks a local chat in the chat list.
    public struct LocalChatBadge: View {
        @Environment(\.hermesPalette) private var palette

        public init() {}

        public var body: some View {
            Label("On this iPhone", systemImage: "iphone")
                .font(HermesFont.caption)
                .foregroundStyle(palette.secondaryText)
                .accessibilityIdentifier("local.badge")
        }
    }
#endif
