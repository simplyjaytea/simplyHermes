#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// A row in the chat list.
    struct SessionRow: View {
        let session: ChatSessionSummary
        let isStreaming: Bool
        let needsApproval: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.title)
                        .font(HermesFont.body.weight(.semibold))
                        .lineLimit(1)
                    if needsApproval {
                        ApprovalDot()
                    }
                    if isStreaming {
                        TypingIndicator()
                            .scaleEffect(0.6)
                    }
                }
                Text("\(session.serverName) · \(session.subtitle)")
                    .font(HermesFont.footnote)
                    .foregroundStyle(HermesColor.secondaryText)
                    .lineLimit(1)
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("session.\(session.id)")
        }
    }

    /// A section the shell has a place for but a later work package fills in.
    struct SectionPlaceholder: View {
        let section: AppSection

        var body: some View {
            if section == .settings {
                // Holds the "Keep bots live" switch until WP-53 builds Settings.
                SettingsPreviewList()
            } else {
                ContentUnavailableView {
                    Label(section.title, systemImage: section.systemImage)
                } description: {
                    Text("Coming in \(section.plannedIn).")
                }
                .navigationTitle(section.title)
            }
        }
    }

    /// Shown in the detail column when no chat is selected.
    struct NoChatSelected: View {
        let onNewChat: () -> Void

        var body: some View {
            ContentUnavailableView {
                Label("No chat selected", systemImage: "bubble.left.and.bubble.right")
            } description: {
                Text("Pick a chat from the sidebar or start a new one.")
            } actions: {
                Button("New chat", action: onNewChat)
                    .buttonStyle(HermesButtonStyle(.primary, fillsWidth: false))
            }
        }
    }

    /// The inner-landscape preview rail: tool output, files and web pages (plan Q4).
    struct PreviewRail: View {
        enum Tab: String, CaseIterable, Identifiable {
            case output = "Output"
            case files = "Files"
            case web = "Web"
            var id: String { rawValue }
        }

        let model: ShellModel
        let sessionID: String?
        @State private var tab: Tab = .output

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Preview", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                switch tab {
                case .output:
                    output
                case .files:
                    ContentUnavailableView("No files yet", systemImage: "doc", description: Text("Coming in WP-32."))
                case .web:
                    ContentUnavailableView("No pages yet", systemImage: "globe", description: Text("Coming in WP-55."))
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .accessibilityIdentifier("previewRail")
        }

        @ViewBuilder
        private var output: some View {
            if outputs.isEmpty {
                ContentUnavailableView(
                    "No output yet",
                    systemImage: "terminal",
                    description: Text("Tool output from this chat shows here.")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(outputs) { output in
                            ToolOutputCard(output: output) { addToChat(output.text) }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }

        /// Every tool call in the chat, newest first. Live chats carry their output; placeholder chats keep it in the transcript.
        private var outputs: [ToolOutput] {
            guard let sessionID else { return [] }
            if let chat = model.liveChat(for: sessionID) {
                return chat.state.items.reversed().compactMap(ToolOutput.init(item:))
            }
            return (model.transcripts[sessionID] ?? []).reversed().compactMap(ToolOutput.init(message:))
        }

        private func addToChat(_ text: String) {
            guard let sessionID else { return }
            let draft = model.drafts[sessionID, default: ""]
            model.drafts[sessionID] = draft.isEmpty ? text : draft + "\n" + text
        }
    }

    /// One tool call's output in the preview rail (WP-36).
    struct ToolOutput: Identifiable, Equatable {
        let id: String
        let command: String
        let isDone: Bool
        let text: String

        init(id: String, command: String, isDone: Bool, text: String) {
            self.id = id
            self.command = command
            self.isDone = isDone
            self.text = text
        }

        init?(item: TranscriptItem) {
            guard case .tool(let entry) = item.content else { return nil }
            self.init(
                id: item.id,
                command: entry.context ?? entry.name,
                isDone: entry.phase == .completed,
                text: entry.resultText ?? entry.summary ?? entry.preview ?? ""
            )
        }

        init?(message: ShellMessage) {
            guard case .tool(let command) = message.kind else { return nil }
            self.init(id: message.id, command: command, isDone: true, text: message.text)
        }
    }

    /// The command, the output and the two actions for one tool call (WP-36).
    private struct ToolOutputCard: View {
        let output: ToolOutput
        let onAddToChat: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(output.command)
                        .font(HermesFont.code.weight(.semibold))
                        .lineLimit(1)
                    if !output.isDone {
                        ProgressView().controlSize(.small)
                    }
                }
                Text(shownText)
                    .font(HermesFont.code)
                    .foregroundStyle(output.text.isEmpty ? HermesColor.secondaryText : HermesColor.primaryText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(HermesColor.fill, in: RoundedRectangle(cornerRadius: HermesMetrics.innerRadius))
                HStack(spacing: 8) {
                    Button("Copy") { UIPasteboard.general.string = output.text }
                        .buttonStyle(HermesButtonStyle(.tinted))
                    Button("Add to chat", action: onAddToChat)
                        .buttonStyle(HermesButtonStyle(.tinted))
                }
                .disabled(output.text.isEmpty)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("toolOutput.\(output.id)")
        }

        /// The first 4000 characters, as the inline tool card shows them. Empty output says why.
        private var shownText: String {
            if output.text.isEmpty { return output.isDone ? "No output" : "Running" }
            return String(output.text.prefix(4000))
        }
    }

    /// Tent posture: a glance at the running task with big Stop, Deny and Approve buttons.
    struct GlanceView: View {
        let model: ShellModel

        var body: some View {
            let sessionID = model.selectedSessionID
            let session = sessionID.flatMap { model.session(id: $0) }
            let approval = sessionID.flatMap { model.pendingApproval(in: $0) }
            let isStreaming = sessionID.map { model.isStreaming($0) } ?? false
            VStack(spacing: 16) {
                if InlineTipStore.isPending(.tent) { InlineTipCard(kind: .tent) }
                Text(session?.title ?? "No chat")
                    .font(HermesFont.glanceTitle)
                    .lineLimit(1)
                Text(isStreaming ? "Hermes is replying" : (approval == nil ? "Idle" : "Waiting for you"))
                    .font(HermesFont.headline)
                    .foregroundStyle(HermesColor.secondaryText)
                if let approval {
                    Text(approval.text)
                        .font(HermesFont.code)
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(HermesColor.fill, in: RoundedRectangle(cornerRadius: HermesMetrics.innerRadius))
                }
                HStack(spacing: 12) {
                    Button("Stop") { if let sessionID { model.stop(in: sessionID) } }
                        .buttonStyle(HermesButtonStyle(.destructive))
                        .disabled(!isStreaming)
                    Button("Deny") { if let sessionID { model.resolveApproval(in: sessionID, approved: false) } }
                        .buttonStyle(HermesButtonStyle(.secondary))
                        .disabled(approval == nil)
                    Button("Approve") { if let sessionID { model.resolveApproval(in: sessionID, approved: true) } }
                        .buttonStyle(HermesButtonStyle(.primary))
                        .disabled(approval == nil)
                }
                .font(HermesFont.headline)
                .controlSize(.large)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(HermesColor.groupedBackground)
            .accessibilityIdentifier("glance")
        }
    }

    /// Open chats as glass capsules above the chat on the inner screen (JT's pick, 2026-10-14).
    struct ChatTabStrip: View {
        let model: ShellModel
        @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
        @Environment(\.hermesReduceMotion) private var reduceMotionOverride

        var body: some View {
            let reduceMotion = HermesMotion.resolveReduceMotion(
                system: systemReduceMotion, override: reduceMotionOverride)
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(model.openSessionIDs, id: \.self) { id in
                        if let session = model.session(id: id) {
                            capsule(for: session, isSelected: id == model.selectedSessionID)
                                .transition(.scale(scale: 0.8).combined(with: .opacity))
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .animation(
                    HermesMotion.animation(HermesMotion.snappy, reduceMotion: reduceMotion), value: model.openSessionIDs
                )
            }
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("tabStrip")
        }

        private func capsule(for session: ChatSessionSummary, isSelected: Bool) -> some View {
            HStack(spacing: 4) {
                Button {
                    model.open(session.id)
                } label: {
                    HStack(spacing: 6) {
                        if model.needsApproval(session.id) {
                            ApprovalDot()
                        } else if model.isStreaming(session.id) {
                            Circle()
                                .fill(HermesColor.accent)
                                .frame(width: 6, height: 6)
                                .accessibilityHidden(true)
                        }
                        Text(session.title)
                            .font(HermesFont.subheadline.weight(isSelected ? .semibold : .regular))
                            .lineLimit(1)
                    }
                    .padding(.leading, 12)
                    .frame(minHeight: HermesMetrics.minTapTarget)
                }
                .buttonStyle(.plain)
                Button {
                    model.close(session.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(HermesColor.secondaryText)
                        .frame(width: HermesMetrics.minTapTarget, height: HermesMetrics.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close \(session.title)"))
                .padding(.trailing, 4)
            }
            .foregroundStyle(isSelected ? HermesColor.accent : HermesColor.primaryText)
            .glassEffect(isSelected ? .regular.tint(HermesColor.accent.opacity(0.15)) : .regular, in: Capsule())
            .accessibilityIdentifier("tab.\(session.id)")
        }
    }
#endif
