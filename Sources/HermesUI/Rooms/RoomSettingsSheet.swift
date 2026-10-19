#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// A group chat's settings: its name, the bots in it, and disband (WP-43 spec, section 6). Members are read here,
    /// not edited, because the server has no add or remove call.
    struct RoomSettingsSheet: View {
        let model: RoomChatModel
        @Environment(\.dismiss) private var dismiss
        @State private var name: String
        @State private var isSaving = false
        @State private var isConfirmingDisband = false
        @State private var errorMessage: String?

        init(model: RoomChatModel) {
            self.model = model
            _name = State(initialValue: model.room.name)
        }

        private var canSave: Bool {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return !isSaving && model.readOnlyNote == nil && !trimmed.isEmpty
                && trimmed.count <= RoomDraft.maxNameLength && trimmed != model.room.name
        }

        var body: some View {
            NavigationStack {
                Form {
                    if let errorMessage {
                        Section {
                            Text(errorMessage)
                                .font(HermesFont.footnote)
                                .foregroundStyle(HermesColor.destructive)
                        }
                    }
                    Section("Name") {
                        TextField("Name", text: $name)
                            .disabled(model.readOnlyNote != nil)
                        Button("Save Name") {
                            Task { await save() }
                        }
                        .disabled(!canSave)
                    }
                    Section("Bots") {
                        ForEach(model.room.members.indices, id: \.self) { index in
                            memberRow(model.room.members[index])
                        }
                    }
                    Section {
                        Button("Disband Group Chat", role: .destructive) {
                            isConfirmingDisband = true
                        }
                        .disabled(model.readOnlyNote != nil)
                    } footer: {
                        Text("Running turns stop first. A disbanded Group Chat cannot be brought back.")
                    }
                }
                .navigationTitle("Group Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .confirmationDialog(
                    "Disband this Group Chat?", isPresented: $isConfirmingDisband, titleVisibility: .visible
                ) {
                    Button("Disband", role: .destructive) {
                        Task { await disband() }
                    }
                } message: {
                    Text("Running turns stop first. A disbanded Group Chat cannot be brought back.")
                }
            }
        }

        private func memberRow(_ member: RoomMember) -> some View {
            HStack(spacing: 12) {
                RoomAvatarView(name: RoomTimeline.label(for: member), profile: member.profile, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(RoomTimeline.label(for: member))
                        .font(HermesFont.body)
                    if let handle = member.handle {
                        Text("@\(handle)")
                            .font(HermesFont.caption)
                            .foregroundStyle(HermesColor.secondaryText)
                    }
                    if member.target?["kind"]?.stringValue == "peer" {
                        Text("Runs on another computer")
                            .font(HermesFont.caption)
                            .foregroundStyle(HermesColor.secondaryText)
                    }
                }
            }
        }

        private func save() async {
            isSaving = true
            defer { isSaving = false }
            do {
                try await model.rename(to: name)
                name = model.room.name
                errorMessage = nil
            } catch {
                errorMessage = RoomFailure.message(for: error)
            }
        }

        private func disband() async {
            do {
                try await model.disband()
                dismiss()
            } catch {
                errorMessage = RoomFailure.message(for: error)
            }
        }
    }
#endif
