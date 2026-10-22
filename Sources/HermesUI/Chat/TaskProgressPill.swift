#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// The agent's todo list above the composer (plan Q20): a glass pill with the count and the current task, which
    /// opens into the full list. The caller hides it when the chat is idle.
    struct TaskProgressPill: View {
        let progress: TaskProgress
        @State private var isOpen = false

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(.snappy) { isOpen.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checklist")
                            .foregroundStyle(HermesColor.accent)
                        Text(progress.summary)
                            .font(HermesFont.caption.monospacedDigit())
                        if let current = progress.current {
                            Text(current.text)
                                .font(HermesFont.caption)
                                .foregroundStyle(HermesColor.secondaryText)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.up")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(HermesColor.secondaryText)
                            .rotationEffect(.degrees(isOpen ? 180 : 0))
                    }
                    .frame(minHeight: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("chat.tasks")
                .accessibilityLabel(Text("Tasks, \(progress.summary) done"))
                .accessibilityHint(Text(isOpen ? "Collapses the list" : "Shows the list"))

                if isOpen {
                    ForEach(progress.items) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: symbol(item.status))
                                .foregroundStyle(
                                    item.status == .done ? HermesColor.statusConnected : HermesColor.secondaryText)
                            Text(item.text)
                                .font(HermesFont.footnote)
                                .strikethrough(item.status == .cancelled)
                                .foregroundStyle(
                                    item.status == .pending ? HermesColor.secondaryText : HermesColor.primaryText)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 10)
        }

        private func symbol(_ status: TaskProgress.Status) -> String {
            switch status {
            case .done: "checkmark.circle.fill"
            case .active: "circle.dotted"
            case .cancelled: "xmark.circle"
            case .pending: "circle"
            }
        }
    }

    /// The settings of the chat, as pills above the composer's field (plan Q19): model, reasoning and workspace.
    /// The model pill is a popup menu (plan Q22). The other pills only show what the server reported. The workspace
    /// pill opens the folder picker (plan Q31).
    struct ComposerPills: View {
        let chat: LiveChatModel
        /// Opens the folder picker. Without it the workspace pill only shows the folder.
        var onWorkspace: (() -> Void)?

        var body: some View {
            if chat.state.info != nil {
                let pills = entries
                let folder = folderName
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ModelPicker(chat: chat)
                        ForEach(pills, id: \.label) { pill in
                            pillLabel(pill.label, symbol: pill.symbol)
                        }
                        if let folder {
                            workspacePill(folder)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .accessibilityIdentifier("composer.pills")
            }
        }

        private func pillLabel(_ label: String, symbol: String) -> some View {
            Label(label, systemImage: symbol)
                .font(HermesFont.caption)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(minHeight: 28)
                .background(HermesColor.fill, in: Capsule())
        }

        @ViewBuilder
        private func workspacePill(_ name: String) -> some View {
            if let onWorkspace {
                Button(action: onWorkspace) {
                    pillLabel(name, symbol: "folder")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("chat.workspace")
                .accessibilityHint(Text("Chooses the folder this chat runs in"))
            } else {
                pillLabel(name, symbol: "folder")
            }
        }

        private var entries: [(label: String, symbol: String)] {
            let info = chat.state.info
            var result: [(String, String)] = []
            if let effort = info?.reasoningEffort, !effort.isEmpty { result.append((effort.capitalized, "brain")) }
            return result
        }

        /// The last part of the folder's path, which is what the pill has room for.
        private var folderName: String? {
            guard let cwd = chat.workspaceCwd ?? chat.state.info?.cwd, !cwd.isEmpty else { return nil }
            return cwd.split(separator: "/").last.map(String.init) ?? cwd
        }
    }
#endif
