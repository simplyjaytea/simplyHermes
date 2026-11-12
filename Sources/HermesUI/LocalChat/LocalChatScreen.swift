#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// A local chat: the saved messages, each reply labelled with the model that wrote it, and a composer. Nothing on
    /// this screen reaches a server.
    public struct LocalChatScreen: View {
        @Bindable var model: LocalChatModel
        @State private var draft = ""
        /// The last "Remember this", for its Undo bar.
        @State private var remembered: LocalMemoryChange?
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
                if let proposal = model.snapshot.memoryProposal { proposalCard(proposal) }
                if let saved = model.snapshot.memoryChange {
                    rememberedBar(saved, undo: { model.undoMemoryChange() }, dismiss: { model.dismissMemoryChange() })
                } else if let remembered {
                    rememberedBar(remembered, undo: { undoRemembered(remembered) }, dismiss: { self.remembered = nil })
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
                        .messageActions(text: message.text, onQuote: quote) { rememberButton(message.text) }
                        .accessibilityIdentifier("local.message.user")
                }
            case .assistant(let identity, _):
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.text)
                        .padding(12)
                        .background(palette.incomingBubble, in: RoundedRectangle(cornerRadius: 16))
                        .messageActions(text: message.text, onQuote: quote) { rememberButton(message.text) }
                    Label(Self.answeredBy(identity), systemImage: "iphone")
                        .font(HermesFont.caption)
                        .foregroundStyle(palette.secondaryText)
                        .accessibilityIdentifier("local.message.model")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        /// "Remember this": saves the message to on-device memory (local chats only, never sent to a server).
        @ViewBuilder
        private func rememberButton(_ text: String) -> some View {
            if let memory = LocalChatServices.shared?.memory, let excerpt = LocalMemoryRules.excerpt(of: text) {
                Button("Remember this", systemImage: "brain") {
                    Task {
                        if let saved = try? await memory.save(excerpt, source: .user, at: Date()) {
                            remembered = .saved(saved)
                        }
                    }
                }
                .accessibilityIdentifier("message.action.remember")
            }
        }

        private func undoRemembered(_ change: LocalMemoryChange) {
            remembered = nil
            if let memory = LocalChatServices.shared?.memory {
                Task { try? await change.undo(in: memory) }
            }
        }

        /// "Save this to memory?": the model wants to save something after reading a file, so the user decides.
        private func proposalCard(_ text: String) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Save this to memory?")
                    .font(HermesFont.footnote.weight(.semibold))
                    .foregroundStyle(palette.primaryText)
                Text(text)
                    .font(HermesFont.footnote)
                    .foregroundStyle(palette.primaryText)
                HStack(spacing: 8) {
                    Button("Save") { model.answerMemoryProposal(save: true) }
                        .buttonStyle(HermesButtonStyle(.primary, fillsWidth: false))
                        .accessibilityIdentifier("memory.proposal.save")
                    Button("Don't save") { model.answerMemoryProposal(save: false) }
                        .buttonStyle(HermesButtonStyle(.tinted, fillsWidth: false))
                        .accessibilityIdentifier("memory.proposal.decline")
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("memory.proposal")
        }

        /// "Saved to memory" with Undo, for 5 s, like the memory list's. Also for a memory the model saved itself.
        private func rememberedBar(
            _ change: LocalMemoryChange, undo: @escaping () -> Void, dismiss: @escaping () -> Void
        ) -> some View {
            HStack {
                Text(change.summary)
                    .font(HermesFont.footnote)
                    .foregroundStyle(palette.primaryText)
                Spacer()
                Button("Undo", action: undo)
                    .accessibilityIdentifier("memory.undo")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: Capsule())
            .padding(.horizontal)
            .accessibilityIdentifier("memory.remembered")
            .task(id: change) {
                try? await Task.sleep(for: .seconds(5))
                if !Task.isCancelled { dismiss() }
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
