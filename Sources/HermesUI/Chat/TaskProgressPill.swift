#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// The agent's todo list above the composer (plan Q20): a glass pill with the count and the current task, which
    /// opens into the full list. The caller hides it when the chat is idle.
    struct TaskProgressPill: View {
        @Environment(\.hermesPalette) private var palette
        let progress: TaskProgress
        @State private var isOpen = false
        @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
        @Environment(\.hermesReduceMotion) private var reduceMotionOverride

        private var reduceMotion: Bool {
            HermesMotion.resolveReduceMotion(system: systemReduceMotion, override: reduceMotionOverride)
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(HermesMotion.animation(HermesMotion.snappy, reduceMotion: reduceMotion)) {
                        isOpen.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checklist")
                            .foregroundStyle(palette.accent)
                        Text(progress.summary)
                            .font(HermesFont.caption.monospacedDigit())
                        if let current = progress.current {
                            Text(current.text)
                                .font(HermesFont.caption)
                                .foregroundStyle(palette.secondaryText)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.up")
                            .font(HermesFont.caption2.weight(.semibold))
                            .foregroundStyle(palette.secondaryText)
                            .rotationEffect(.degrees(isOpen ? 180 : 0))
                    }
                    .frame(minHeight: HermesMetrics.minTapTarget)
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
                                    item.status == .done ? palette.statusConnected : palette.secondaryText)
                            Text(item.text)
                                .font(HermesFont.footnote)
                                .strikethrough(item.status == .cancelled)
                                .foregroundStyle(
                                    item.status == .pending ? palette.secondaryText : palette.primaryText)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: HermesMetrics.cardRadius, style: .continuous))
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
        @Environment(\.hermesPalette) private var palette
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
                .background(palette.fill, in: Capsule())
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
