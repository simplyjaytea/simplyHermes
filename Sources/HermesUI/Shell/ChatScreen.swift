#if canImport(UIKit)
    import SwiftUI

    /// One chat: transcript, status strip and composer. The half-fold style moves the composer
    /// and quick actions to the bottom half (plan Q5). WP-30 replaces the placeholder transcript.
    struct ChatScreen: View {
        enum Style {
            case standard
            case halfFold
        }

        @Bindable var model: ShellModel
        let sessionID: String
        var style: Style = .standard

        @State private var position = ScrollPosition(idType: String.self)
        /// True while the transcript sticks to the newest text. A drag stops it; settling at the bottom resumes it.
        @State private var isFollowing = true
        @State private var visibleIDs: [String] = []
        /// True from the user's touch until the scroll comes to rest; programmatic scrolls never set it.
        @State private var isUserScrolling = false

        var body: some View {
            if let live = model.liveChat(for: sessionID) {
                LiveChatScreen(chat: live, model: model, sessionID: sessionID, style: style)
            } else {
                placeholder
            }
        }

        @ViewBuilder
        private var placeholder: some View {
            switch style {
            case .standard:
                VStack(spacing: 0) {
                    transcript
                    Composer(text: model.draftBinding(for: sessionID)) { model.send(in: sessionID) }
                        .background(HermesColor.background)
                }
            case .halfFold:
                VStack(spacing: 0) {
                    transcript
                        .frame(maxHeight: .infinity)
                    Divider()
                    VStack(spacing: 8) {
                        Composer(text: model.draftBinding(for: sessionID)) { model.send(in: sessionID) }
                        QuickActions(model: model, sessionID: sessionID)
                            .padding(.horizontal, 12)
                    }
                    .padding(.bottom, 8)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(HermesColor.groupedBackground)
                }
            }
        }

        private var transcript: some View {
            ScrollView {
                LazyVStack(spacing: HermesMetrics.bubbleSpacing) {
                    ForEach(model.transcripts[sessionID] ?? []) { message in
                        row(for: message)
                            .accessibilityIdentifier("message.\(message.id)")
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 12)
            }
            // On the scroll view itself, so UI tests can swipe it (on the outer view it lands on the status strip).
            .accessibilityIdentifier("transcript")
            .scrollPosition($position)
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .defaultScrollAnchor(.bottom, for: .alignment)
            .onScrollTargetVisibilityChange(idType: String.self, threshold: 0.1) { ids in
                visibleIDs = ids
            }
            // Only the user's own scrolling moves the saved position, so streaming never fights their finger.
            .onScrollPhaseChange { _, phase, context in
                switch phase {
                case .tracking, .interacting:
                    isFollowing = false
                    isUserScrolling = true
                case .idle:
                    guard isUserScrolling else { return }
                    isUserScrolling = false
                    let geometry = context.geometry
                    let atBottom = geometry.visibleRect.maxY >= geometry.contentSize.height - 40
                    isFollowing = atBottom
                    model.scrollAnchors[sessionID] = atBottom ? nil : topVisibleID
                default:
                    break
                }
            }
            .task {
                guard let anchor = model.scrollAnchors[sessionID] else { return }
                isFollowing = false
                position.scrollTo(id: anchor, anchor: .top)
                // Again once the lazy rows have laid out after a fold.
                try? await Task.sleep(for: .milliseconds(150))
                position.scrollTo(id: anchor, anchor: .top)
            }
            .onChange(of: model.transcripts[sessionID]?.last?.text) {
                if isFollowing {
                    position.scrollTo(edge: .bottom)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .top) {
                if let session = model.session(id: sessionID) {
                    StatusStrip(
                        connection: .connected,
                        serverName: session.serverName,
                        runningTurn: model.isStreaming(sessionID) ? "Hermes is replying" : nil,
                        onStop: model.isStreaming(sessionID) ? { model.stop(in: sessionID) } : nil
                    )
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                }
            }
        }

        /// The first message on screen, in transcript order. Restoring puts it back at the top.
        private var topVisibleID: String? {
            let messages = model.transcripts[sessionID] ?? []
            return messages.first { visibleIDs.contains($0.id) }?.id
        }

        @ViewBuilder
        private func row(for message: ShellMessage) -> some View {
            switch message.kind {
            case .user:
                MessageBubble(role: .user, text: message.text)
            case .assistant:
                MessageBubble(role: .assistant, text: message.text)
            case .tool(let command):
                ToolOutputBubble(command: command, output: message.text)
            case .approval:
                ApprovalBubble(
                    command: message.text,
                    onDeny: { model.resolveApproval(in: sessionID, approved: false) },
                    onApprove: { model.resolveApproval(in: sessionID, approved: true) }
                )
            }
        }
    }

    /// The six half-fold quick actions: Approve, Deny, Stop, Voice, Attach, Terminal.
    struct QuickActions: View {
        let model: ShellModel
        let sessionID: String

        var body: some View {
            let hasApproval = model.pendingApproval(in: sessionID) != nil
            let isStreaming = model.isStreaming(sessionID)
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    action("Approve", "checkmark", kind: .primary, enabled: hasApproval) {
                        model.resolveApproval(in: sessionID, approved: true)
                    }
                    action("Deny", "xmark", kind: .secondary, enabled: hasApproval) {
                        model.resolveApproval(in: sessionID, approved: false)
                    }
                    action("Stop", "stop.fill", kind: .destructive, enabled: isStreaming) {
                        model.stop(in: sessionID)
                    }
                }
                GridRow {
                    // Voice is WP-60, attachments WP-32, terminal WP-52.
                    action("Voice", "mic", kind: .tinted, enabled: false) {}
                    action("Attach", "paperclip", kind: .tinted, enabled: false) {}
                    action("Terminal", "terminal", kind: .tinted, enabled: false) {}
                }
            }
        }

        private func action(
            _ title: String,
            _ systemImage: String,
            kind: HermesButtonStyle.Kind,
            enabled: Bool,
            perform: @escaping () -> Void
        ) -> some View {
            Button(action: perform) {
                Label(title, systemImage: systemImage)
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(HermesButtonStyle(kind))
            .disabled(!enabled)
            .accessibilityIdentifier("quick.\(title.lowercased())")
        }
    }
#endif
