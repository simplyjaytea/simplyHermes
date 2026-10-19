#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// One row of a server chat.
    struct TranscriptRow: View {
        let item: TranscriptItem
        var isLast = false
        @Bindable var chat: LiveChatModel

        var body: some View {
            switch item.content {
            case .user(let entry):
                UserRow(entry: entry, chat: chat)
            case .assistant(let entry):
                AssistantRow(entry: entry, isLast: isLast, chat: chat)
            case .tool(let entry):
                ToolCallRow(entry: entry)
            case .other(let role, let text):
                Text("\(role): \(text)")
                    .font(HermesFont.caption)
                    .foregroundStyle(HermesColor.secondaryText)
                    .bubbleRow(.leading)
            }
        }
    }

    private struct UserRow: View {
        let entry: UserEntry
        @Bindable var chat: LiveChatModel
        @State private var isEditing = false
        @State private var draft = ""

        var body: some View {
            if let kind = entry.displayKind {
                // Cron and delegation prompts are started by the gateway, not typed by the user.
                Label(Self.title(for: kind), systemImage: "clock.arrow.circlepath")
                    .font(HermesFont.caption)
                    .foregroundStyle(HermesColor.secondaryText)
                    .padding(.horizontal, HermesMetrics.bubbleHorizontalPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(Text("\(Self.title(for: kind)): \(entry.text)"))
            } else {
                VStack(alignment: .trailing, spacing: 2) {
                    MessageBubble(role: .user, text: entry.text, rendersMarkdown: true)
                        .contextMenu {
                            if let rowID = entry.rowID {
                                Button("Edit", systemImage: "pencil") {
                                    // An edit that did not go through comes back as the user typed it.
                                    draft = chat.unsentEdits[rowID] ?? entry.text
                                    isEditing = true
                                }
                                .disabled(chat.isRunning)
                            }
                        }
                    if let note = Self.note(for: entry.delivery) {
                        Text(note.text)
                            .font(HermesFont.caption2)
                            .foregroundStyle(note.isError ? HermesColor.destructive : HermesColor.secondaryText)
                            .padding(.horizontal, HermesMetrics.bubbleHorizontalPadding)
                    }
                }
                .sheet(isPresented: $isEditing) { editSheet }
            }
        }

        /// Edit sends the changed turn and cuts the chat after it (WP-34). Empty text is not sent.
        private var editSheet: some View {
            let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            return NavigationStack {
                TextEditor(text: $draft)
                    .font(HermesFont.body)
                    .padding()
                    .navigationTitle("Edit message")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { isEditing = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Send") {
                                if let rowID = entry.rowID { chat.edit(rowID: rowID, text: trimmed) }
                                isEditing = false
                            }
                            .disabled(trimmed.isEmpty)
                        }
                    }
            }
        }

        private static func title(for kind: String) -> LocalizedStringKey {
            switch kind {
            case "cron": "Scheduled task"
            case "delegation": "Delegated task"
            default: "Started by Hermes"
            }
        }

        private static func note(for delivery: UserEntry.Delivery) -> (text: LocalizedStringKey, isError: Bool)? {
            switch delivery {
            case .sending: ("Sending", false)
            case .sent: nil
            case .queued: ("Queued until Hermes is free", false)
            case .failed: ("Not sent", true)
            }
        }
    }

    private struct AssistantRow: View {
        let entry: AssistantEntry
        let isLast: Bool
        @Bindable var chat: LiveChatModel
        @State private var showsReasoning = false

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                if let reasoning = entry.reasoning, !reasoning.isEmpty {
                    DisclosureGroup(isExpanded: $showsReasoning) {
                        Text(reasoning)
                            .font(HermesFont.footnote)
                            .foregroundStyle(HermesColor.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        Label("Reasoning", systemImage: "brain")
                            .font(HermesFont.footnote)
                            .foregroundStyle(HermesColor.secondaryText)
                    }
                    .padding(.horizontal, HermesMetrics.bubbleHorizontalPadding)
                    .bubbleRow(.leading)
                }
                if !entry.text.isEmpty || entry.isStreaming {
                    if entry.text.isEmpty {
                        TypingIndicator().bubbleRow(.leading)
                    } else {
                        StreamingText(text: entry.text, isStreaming: entry.isStreaming, rendersMarkdown: true)
                    }
                }
                if let error = entry.error, !error.isEmpty {
                    ErrorCard(error: ChatError.classify(error), isLast: isLast, chat: chat)
                } else if entry.status == .interrupted {
                    Text("Stopped")
                        .font(HermesFont.caption)
                        .foregroundStyle(HermesColor.secondaryText)
                        .padding(.horizontal, HermesMetrics.bubbleHorizontalPadding)
                }
            }
            // Regenerate runs the last user turn again, so it lives on the last reply (WP-34).
            .contextMenu {
                if isLast {
                    Button("Regenerate", systemImage: "arrow.clockwise") { chat.regenerate() }
                        .disabled(chat.isRunning || entry.isStreaming)
                }
            }
        }
    }

    private struct ToolCallRow: View {
        let entry: ToolEntry
        @State private var isExpanded = false

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(HermesMotion.snappy) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        icon
                        Text(entry.name)
                            .font(HermesFont.codeSmall.weight(.semibold))
                        if let context = entry.context, !context.isEmpty {
                            Text(context)
                                .font(HermesFont.codeSmall)
                                .foregroundStyle(HermesColor.secondaryText)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        if let seconds = entry.durationSeconds {
                            Text(String(format: "%.1fs", seconds))
                                .font(HermesFont.caption)
                                .foregroundStyle(HermesColor.secondaryText)
                        }
                        Image(systemName: "chevron.right")
                            .font(HermesFont.caption)
                            .foregroundStyle(HermesColor.secondaryText)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                    .frame(minHeight: HermesMetrics.minTapTarget - 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("\(entry.name), \(statusText)"))
                .accessibilityHint(Text(isExpanded ? "Hides the output" : "Shows the output"))
                if isExpanded, let body = detail {
                    Text(body)
                        .font(HermesFont.codeSmall)
                        .foregroundStyle(HermesColor.primaryText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, HermesMetrics.bubbleHorizontalPadding)
            .padding(.vertical, 6)
            .background(
                HermesColor.incomingBubble,
                in: RoundedRectangle(cornerRadius: HermesMetrics.bubbleRadius, style: .continuous)
            )
            .bubbleRow(.leading)
        }

        @ViewBuilder
        private var icon: some View {
            switch entry.phase {
            case .generating, .running:
                ProgressView().controlSize(.small)
            case .completed:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(HermesColor.statusConnected)
            }
        }

        private var statusText: LocalizedStringKey {
            switch entry.phase {
            case .generating: "preparing"
            case .running: "running"
            case .completed: "done"
            }
        }

        /// The text the card opens to: the diff for file edits, else the output, else the summary.
        private var detail: String? {
            let text = entry.inlineDiff ?? entry.resultText ?? entry.summary ?? entry.preview
            guard let text, !text.isEmpty else { return nil }
            return String(text.prefix(4000))
        }
    }
#endif
