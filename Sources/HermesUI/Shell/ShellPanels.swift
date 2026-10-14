#if canImport(UIKit)
    import SwiftUI

    /// A row in the chat list.
    struct SessionRow: View {
        let session: ChatSessionSummary
        let isStreaming: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.title)
                        .font(HermesFont.body.weight(.semibold))
                        .lineLimit(1)
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
            ContentUnavailableView {
                Label(section.title, systemImage: section.systemImage)
            } description: {
                Text("Coming in \(section.plannedIn).")
            }
            .navigationTitle(section.title)
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

    /// The inner-landscape preview rail: latest tool output, files and web pages (plan Q4).
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
            if let latest = latestToolOutput {
                VStack(alignment: .leading, spacing: 8) {
                    Text(latest.command)
                        .font(HermesFont.code.weight(.semibold))
                    ScrollView {
                        Text(latest.output)
                            .font(HermesFont.code)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(10)
                    .background(HermesColor.fill, in: RoundedRectangle(cornerRadius: HermesMetrics.innerRadius))
                    HStack(spacing: 8) {
                        Button("Copy") { UIPasteboard.general.string = latest.output }
                            .buttonStyle(HermesButtonStyle(.tinted))
                        Button("Add to chat") {
                            guard let sessionID else { return }
                            let draft = model.drafts[sessionID, default: ""]
                            model.drafts[sessionID] = draft.isEmpty ? latest.output : draft + "\n" + latest.output
                        }
                        .buttonStyle(HermesButtonStyle(.tinted))
                    }
                }
            } else {
                ContentUnavailableView(
                    "No output yet",
                    systemImage: "terminal",
                    description: Text("Tool output from this chat shows here.")
                )
            }
        }

        private var latestToolOutput: (command: String, output: String)? {
            guard let sessionID, let messages = model.transcripts[sessionID] else { return nil }
            for message in messages.reversed() {
                if case .tool(let command) = message.kind {
                    return (command, message.text)
                }
            }
            return nil
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
#endif
