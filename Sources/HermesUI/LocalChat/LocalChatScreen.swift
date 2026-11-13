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
                if let note = failureNote {
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

        /// A question with no reply: its reply failed, or the app stopped before one came. Retry asks again for it alone.
        private func noReplyRow(_ question: Int) -> some View {
            HStack {
                Text("No reply")
                    .font(HermesFont.footnote)
                    .foregroundStyle(palette.errorText)
                    .accessibilityIdentifier("local.noReply")
                Spacer()
                Button("Retry") { model.retry(messageID: question) }
                    .buttonStyle(HermesButtonStyle(.primary, fillsWidth: false))
                    .accessibilityIdentifier("local.retry")
            }
            .padding(.horizontal)
        }

        /// "Reply to: <first line of the question>", shown above a reply that does not directly follow its question, so
        /// a late answer below a newer one still says what it answers.
        private func replyHeader(_ question: Int) -> some View {
            Text("Reply to: \(Self.preview(of: questionText(question)))")
                .font(HermesFont.caption)
                .foregroundStyle(palette.secondaryText)
                .accessibleLineLimit()
                .accessibilityIdentifier("local.replyTo")
        }

        private func questionText(_ question: Int) -> String? {
            model.snapshot.messages.first { $0.id == question }?.text
        }

        /// The first line of `text`, cut to 60 characters. Nil text reads as an earlier message.
        static func preview(of text: String?) -> String {
            guard
                let line = text?.split(whereSeparator: \.isNewline).first.map(String.init)?
                    .trimmingCharacters(in: .whitespaces), !line.isEmpty
            else { return "an earlier message" }
            return line.count > 60 ? String(line.prefix(60)) + "…" : line
        }

        /// The question a reply answers, or nil for a user message.
        private func questionOf(_ message: LocalChatMessage) -> Int? {
            if case .assistant(_, let question) = message.author { return question }
            return nil
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
                    let messages = model.snapshot.messages
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        if let question = questionOf(message), index == 0 || messages[index - 1].id != question {
                            replyHeader(question)
                        }
                        row(message)
                        if model.snapshot.unansweredIDs.contains(message.id) {
                            noReplyRow(message.id)
                        }
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
                    // Long-press opens the message menu; partial copy is its Select text sheet.
                    Text(message.text)
                        .padding(12)
                        .background(palette.outgoingBubble, in: RoundedRectangle(cornerRadius: 16))
                        .messageActions(text: message.text, onQuote: quote)
                        .accessibilityIdentifier("local.message.user")
                }
            case .assistant(let identity, _):
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.text)
                        .padding(12)
                        .background(palette.incomingBubble, in: RoundedRectangle(cornerRadius: 16))
                        .messageActions(text: message.text, onQuote: quote)
                    Label(Self.answeredBy(identity), systemImage: "iphone")
                        .font(HermesFont.caption)
                        .foregroundStyle(palette.secondaryText)
                        .accessibilityIdentifier("local.message.model")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        /// "Quote in reply": the quote goes in front of the draft. Nothing is sent.
        private func quote(_ text: String) {
            draft = MessageQuote.inserting(text, into: draft)
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
            case .unavailable(.noModelChosen): "No on-device model is in use. Pick one in Settings to get a reply here."
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
