#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// A server chat: the transcript with approval cards inline, then the composer (WP-30).
    struct LiveChatScreen: View {
        @Bindable var chat: LiveChatModel
        @Bindable var model: ShellModel
        let sessionID: String
        var style: ChatScreen.Style = .standard

        @State private var position = ScrollPosition(idType: String.self)
        @State private var isFollowing = true
        @State private var isUserScrolling = false

        var body: some View {
            VStack(spacing: 0) {
                content
                    .frame(maxHeight: .infinity)
                if style == .halfFold { Divider() }
                Composer(text: model.draftBinding(for: sessionID)) { send() }
                    .background(HermesColor.background)
            }
            .task(id: sessionID) { await chat.attach() }
        }

        @ViewBuilder
        private var content: some View {
            switch chat.phase {
            case .loading where chat.state.items.isEmpty:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Could not open this chat", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await chat.attach() } }
                        .buttonStyle(HermesButtonStyle(.primary))
                }
            default:
                transcript
            }
        }

        private var transcript: some View {
            ScrollView {
                LazyVStack(spacing: HermesMetrics.bubbleSpacing) {
                    ForEach(chat.state.items) { item in
                        TranscriptRow(item: item)
                            .accessibilityIdentifier("message.\(item.id)")
                    }
                    ForEach(chat.approvals) { approval in
                        ApprovalBubble(
                            command: approval.command,
                            onDeny: { chat.answer(approval, .deny) },
                            onApprove: { chat.answer(approval, .once) }
                        )
                        .accessibilityIdentifier("approval.\(approval.id)")
                    }
                    if chat.isRunning, chat.state.items.last.map(Self.isStreamingAssistant) != true {
                        TypingIndicator().bubbleRow(.leading)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .scrollTargetLayout()
                .padding(.vertical, 12)
            }
            .accessibilityIdentifier("transcript")
            .scrollPosition($position)
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .defaultScrollAnchor(.bottom, for: .alignment)
            // Only the user's own scrolling stops the follow, so streaming never fights their finger.
            .onScrollPhaseChange { _, phase, context in
                switch phase {
                case .tracking, .interacting:
                    isFollowing = false
                    isUserScrolling = true
                case .idle:
                    guard isUserScrolling else { return }
                    isUserScrolling = false
                    let geometry = context.geometry
                    isFollowing = geometry.visibleRect.maxY >= geometry.contentSize.height - 40
                default:
                    break
                }
            }
            .onChange(of: followKey) {
                if isFollowing { position.scrollTo(edge: .bottom) }
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .top) { header }
        }

        @ViewBuilder
        private var header: some View {
            if let session = model.session(id: sessionID) {
                StatusStrip(
                    connection: .connected,
                    serverName: session.serverName,
                    runningTurn: chat.isRunning ? "Hermes is replying" : nil,
                    onStop: chat.isRunning ? { chat.stop() } : nil
                )
                .padding(.horizontal, 12)
                .padding(.top, 4)
            }
        }

        /// Changes whenever the bottom of the transcript moves: a new row, new text, or an approval card.
        private var followKey: Int {
            var hasher = Hasher()
            hasher.combine(chat.state.items.count)
            hasher.combine(chat.approvals.count)
            if case .assistant(let entry)? = chat.state.items.last?.content { hasher.combine(entry.text.count) }
            return hasher.finalize()
        }

        private static func isStreamingAssistant(_ item: TranscriptItem) -> Bool {
            if case .assistant(let entry) = item.content { return entry.isStreaming }
            return false
        }

        private func send() {
            let text = model.drafts[sessionID, default: ""]
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            model.drafts[sessionID] = ""
            isFollowing = true
            chat.send(text)
        }
    }
#endif
