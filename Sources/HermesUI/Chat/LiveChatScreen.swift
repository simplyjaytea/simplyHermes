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
                OfflineBar(chat: chat)
                ChatStatusBar(strip: chat.strip)
                if chat.isRunning, let tasks = TaskProgress(chat.state.todos?.todos ?? []) {
                    TaskProgressPill(progress: tasks)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                ComposerPills(info: chat.state.info)
                Composer(
                    text: model.draftBinding(for: sessionID),
                    attachments: model.attachmentsBinding(for: sessionID),
                    onSend: { send() },
                    // Files cannot be steered into the running reply, so they wait for the queue.
                    onSteer: chat.isRunning && model.attachments[sessionID, default: []].isEmpty ? { steer() } : nil
                )
                .background(HermesColor.background)
            }
            .task(id: sessionID) { await chat.attach() }
            .sheet(item: Binding(get: { chat.valueRequests.first }, set: { _ in })) { item in
                SecureValueSheet(
                    item: item, onSend: { chat.answerValue(item, $0) }, onCancel: { chat.dismissValue(item) })
            }
        }

        @ViewBuilder
        private var content: some View {
            switch chat.phase {
            case .loading where chat.state.items.isEmpty:
                TranscriptSkeleton()
            case .failed where chat.offline.notice != nil:
                // Offline chat (WP-65b): while the server is out of reach, it takes the place of the error.
                transcript
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
                        TranscriptRow(item: item, isLast: item.id == chat.state.items.last?.id, chat: chat)
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
                    if let failure = chat.state.lastError, !chat.isRunning, !Self.lastRowShowsError(chat.state) {
                        ErrorCard(error: ChatError.classify(failure), isLast: true, chat: chat)
                    }
                    if !chat.state.subagents.isEmpty {
                        SubagentBlock(chat: chat)
                    }
                    ForEach(chat.clarifies) { item in
                        ClarifyCard(item: item) { chat.answerClarify(item, $0) }
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
                    OfflineChatSection(model: chat.offline, showsHint: chat.state.items.isEmpty)
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
            .overlay(alignment: .bottomTrailing) { scrollToBottomButton }
        }

        /// Shows after the user scrolls up from the live end, and jumps back to it.
        @ViewBuilder
        private var scrollToBottomButton: some View {
            if !isFollowing, !chat.state.items.isEmpty {
                Button {
                    isFollowing = true
                    withAnimation(.snappy) { position.scrollTo(edge: .bottom) }
                } label: {
                    Image(systemName: "arrow.down")
                        .font(.body.weight(.semibold))
                        .frame(width: HermesMetrics.minTapTarget, height: HermesMetrics.minTapTarget)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular, in: Circle())
                .padding(12)
                .accessibilityIdentifier("chat.scrollToBottom")
                .accessibilityLabel(Text("Scroll to latest"))
                .transition(.scale.combined(with: .opacity))
            }
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
            hasher.combine(chat.offline.messages.count)
            if case .assistant(let entry)? = chat.state.items.last?.content { hasher.combine(entry.text.count) }
            return hasher.finalize()
        }

        /// True when the newest assistant row already carries the error, so the card is not shown twice.
        private static func lastRowShowsError(_ state: TranscriptState) -> Bool {
            if case .assistant(let entry)? = state.items.last?.content { return entry.error?.isEmpty == false }
            return false
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
            let files = model.attachments[sessionID, default: []]
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !files.isEmpty else { return }
            model.drafts[sessionID] = ""
            model.attachments[sessionID] = []
            isFollowing = true
            chat.send(text, attachments: files)
        }
    }
#endif
