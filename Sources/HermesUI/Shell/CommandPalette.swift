#if canImport(UIKit)
    import SwiftUI

    /// The ⌘K command palette: every shell action, searchable.
    struct CommandPalette: View {
        struct Command: Identifiable {
            let id: String
            let title: String
            let systemImage: String
            let shortcut: String?
            let perform: () -> Void
        }

        @Bindable var model: ShellModel
        @Environment(\.dismiss) private var dismiss
        @Environment(\.openWindow) private var openWindow
        @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows
        @State private var query = ""

        var body: some View {
            NavigationStack {
                List(filtered) { command in
                    Button {
                        dismiss()
                        command.perform()
                    } label: {
                        HStack {
                            Label(command.title, systemImage: command.systemImage)
                                .foregroundStyle(HermesColor.primaryText)
                            Spacer()
                            if let shortcut = command.shortcut {
                                Text(shortcut)
                                    .font(HermesFont.footnote)
                                    .foregroundStyle(HermesColor.secondaryText)
                            }
                        }
                    }
                    .accessibilityIdentifier("palette.\(command.id)")
                }
                .searchable(
                    text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search commands"
                )
                .navigationTitle("Commands")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }

        private var filtered: [Command] {
            let all = commands
            guard !query.isEmpty else { return all }
            return all.filter { $0.title.localizedCaseInsensitiveContains(query) }
        }

        private var commands: [Command] {
            var list: [Command] = [
                Command(id: "new", title: "New chat", systemImage: "square.and.pencil", shortcut: "⌘N") {
                    model.newChat()
                }
            ]
            if model.canReopenClosed {
                list.append(
                    Command(
                        id: "reopen", title: "Reopen closed chat", systemImage: "arrow.uturn.backward", shortcut: "⇧⌘T"
                    ) {
                        model.reopenLastClosed()
                    }
                )
            }
            if let selected = model.selectedSessionID {
                list.append(
                    Command(id: "close", title: "Close chat", systemImage: "xmark", shortcut: "⌘W") {
                        model.close(selected)
                    }
                )
                if supportsMultipleWindows {
                    list.append(
                        Command(
                            id: "window", title: "Open chat in new window", systemImage: "macwindow.badge.plus",
                            shortcut: nil
                        ) {
                            openWindow(id: ShellWindow.chat, value: selected)
                        }
                    )
                }
            }
            list.append(
                Command(
                    id: "rail",
                    title: model.showsPreviewRail ? "Hide preview rail" : "Show preview rail",
                    systemImage: "sidebar.trailing",
                    shortcut: "⌥⌘0"
                ) {
                    model.showsPreviewRail.toggle()
                }
            )
            for id in model.openSessionIDs where id != model.selectedSessionID {
                if let session = model.session(id: id) {
                    list.append(
                        Command(
                            id: "open.\(id)", title: "Go to \(session.title)", systemImage: "bubble.left", shortcut: nil
                        ) {
                            model.open(id)
                        }
                    )
                }
            }
            for (index, section) in AppSection.allCases.enumerated() {
                list.append(
                    Command(
                        id: "section.\(section.rawValue)",
                        title: "Go to \(section.title)",
                        systemImage: section.systemImage,
                        shortcut: "⌘\(index + 1)"
                    ) {
                        model.selectedSection = section
                    }
                )
            }
            return list
        }
    }

    /// Scene ids the app declares.
    public enum ShellWindow {
        /// A second window showing one chat, for Split View on the inner screen.
        public static let chat = "chat"
    }
#endif
