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
        @State private var isFinding = false
        @State private var query = ""
        @State private var currentMatch: String?
        @FocusState private var findFocused: Bool

        var body: some View {
            VStack(spacing: 0) {
                content
                    .frame(maxHeight: .infinity)
                if style == .halfFold { Divider() }
                if !chat.queue.isEmpty {
                    QueuedMessagesView(chat: chat)
                }
                ChatStatusBar(strip: chat.strip)
                Composer(
                    text: model.draftBinding(for: sessionID), onSend: { send() },
                    onSteer: chat.isRunning ? { steer() } : nil
                )
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
                            .overlay {
                                if isFinding, item.id == currentMatch {
                                    RoundedRectangle(cornerRadius: HermesMetrics.bubbleRadius, style: .continuous)
                                        .strokeBorder(HermesColor.accent, lineWidth: 2)
                                        .padding(.horizontal, 6)
                                }
                            }
                            .id(item.id)
                            .accessibilityIdentifier("message.\(item.id)")
                    }
                    if !chat.state.subagents.isEmpty {
                        SubagentBlock(chat: chat)
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
            .safeAreaInset(edge: .top) {
                VStack(spacing: 6) {
                    header
                    findBar
                }
            }
            .overlay(alignment: .topTrailing) { findButton }
        }

        private var matches: [String] {
            TranscriptSearch.matchingIDs(in: chat.state.items, query: query)
        }

        @ViewBuilder
        private var findButton: some View {
            if !isFinding, !chat.state.items.isEmpty {
                Button {
                    isFinding = true
                    findFocused = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .frame(width: HermesMetrics.minTapTarget, height: HermesMetrics.minTapTarget)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular, in: Circle())
                .padding(.trailing, 12)
                .padding(.top, 56)
                .accessibilityLabel(Text("Find in chat"))
                .accessibilityIdentifier("chat.find")
            }
        }

        @ViewBuilder
        private var findBar: some View {
            if isFinding {
                HStack(spacing: 8) {
                    TextField("Find in chat", text: $query)
                        .focused($findFocused)
                        .submitLabel(.search)
                        .onSubmit { move(forward: true) }
                        .accessibilityIdentifier("find.field")
                    if !query.isEmpty {
                        Text(matches.isEmpty ? "No matches" : "\(index(of: currentMatch)) of \(matches.count)")
                            .font(HermesFont.caption.monospacedDigit())
                            .foregroundStyle(HermesColor.secondaryText)
                    }
                    Button {
                        move(forward: false)
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(matches.isEmpty)
                    .accessibilityLabel(Text("Previous match"))
                    Button {
                        move(forward: true)
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .disabled(matches.isEmpty)
                    .accessibilityLabel(Text("Next match"))
                    Button("Done") {
                        isFinding = false
                        query = ""
                        currentMatch = nil
                    }
                }
                .padding(.horizontal, 14)
                .frame(minHeight: HermesMetrics.minTapTarget)
                .glassEffect(.regular, in: Capsule())
                .padding(.horizontal, 12)
                .onChange(of: query) {
                    currentMatch = matches.last
                    jump()
                }
            }
        }

        private func index(of id: String?) -> Int {
            id.flatMap { matches.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
        }

        private func move(forward: Bool) {
            currentMatch =
                forward
                ? TranscriptSearch.next(after: currentMatch, in: matches)
                : TranscriptSearch.previous(before: currentMatch, in: matches)
            jump()
        }

        private func jump() {
            guard let currentMatch else { return }
            isFollowing = false
            withAnimation(HermesMotion.snappy) { position.scrollTo(id: currentMatch, anchor: .center) }
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

        private func steer() {
            let text = model.drafts[sessionID, default: ""]
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            model.drafts[sessionID] = ""
            chat.steer(text)
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
