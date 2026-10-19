#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// The Edit sheet for one bot: name, role, avatar, pinned and hidden. Saving writes only what changed.
    struct BotEditSheet: View {
        let model: BotsModel
        let entry: BotRosterEntry
        @Environment(\.dismiss) private var dismiss
        @State private var edit: BotEdit
        @State private var isSaving = false

        init(model: BotsModel, entry: BotRosterEntry) {
            self.model = model
            self.entry = entry
            _edit = State(initialValue: BotEdit(entry: entry))
        }

        var body: some View {
            NavigationStack {
                Form {
                    Section("Name") {
                        TextField("Name", text: $edit.title)
                    }
                    Section("Role") {
                        TextField("What this bot is for", text: $edit.role, axis: .vertical)
                    }
                    Section("Avatar") {
                        AvatarPicker(
                            avatar: $edit.avatar, name: edit.title.isEmpty ? entry.profile : edit.title,
                            tint: entry.tint)
                    }
                    Section {
                        Toggle("Pinned", isOn: $edit.isPinned)
                        Toggle("Hidden", isOn: $edit.isHidden)
                    } footer: {
                        Text("Hidden bots move to the bottom of the list. They still answer to their handle.")
                    }
                }
                .navigationTitle(entry.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { Task { await save() } }
                            .disabled(isSaving)
                    }
                }
            }
        }

        private func save() async {
            isSaving = true
            defer { isSaving = false }
            var trimmed = edit
            trimmed.title = edit.title.trimmingCharacters(in: .whitespacesAndNewlines)
            trimmed.role = edit.role.trimmingCharacters(in: .whitespacesAndNewlines)
            if await model.saveEdits(of: entry, edit: trimmed) { dismiss() }
        }
    }
#endif
