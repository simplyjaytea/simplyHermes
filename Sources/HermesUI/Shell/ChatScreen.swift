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

        var body: some View {
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
                            .id(message.id)
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 12)
            }
            .scrollPosition(id: model.scrollAnchorBinding(for: sessionID), anchor: .bottom)
            .defaultScrollAnchor(.bottom)
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
            .accessibilityIdentifier("transcript")
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
