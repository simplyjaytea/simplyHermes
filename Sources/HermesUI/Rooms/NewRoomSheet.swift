#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// Makes a group chat from the bots of the active gateway (WP-43 spec, section 1). The room id is made once per sheet,
    /// so a retry after a failure makes the same room.
    struct NewRoomSheet: View {
        let model: RoomsModel
        /// The bots a group can take: one per profile on the active gateway.
        let candidates: [RoomMember]
        @Environment(\.dismiss) private var dismiss
        @State private var name = ""
        @State private var chosenProfiles: Set<String> = []
        @State private var roomID = RoomIdentifier.newRoomID()
        @State private var isCreating = false
        @State private var errorMessage: String?

        private var draft: RoomDraft {
            RoomDraft(name: name, members: candidates.filter { chosenProfiles.contains($0.profile ?? "") })
        }

        var body: some View {
            NavigationStack {
                Form {
                    Section {
                        TextField("Name", text: $name)
                    } footer: {
                        Text("Leave the name blank to use the bots' names.")
                    }
                    Section {
                        ForEach(candidates.indices, id: \.self) { index in
                            Toggle(
                                RoomTimeline.label(for: candidates[index]),
                                isOn: binding(forProfile: candidates[index].profile ?? ""))
                        }
                    } header: {
                        Text("Bots")
                    } footer: {
                        Text(draft.problems().first?.message ?? "Ready to make the group.")
                    }
                    if let errorMessage {
                        Section {
                            Text(errorMessage)
                                .font(HermesFont.footnote)
                                .foregroundStyle(HermesColor.destructive)
                        }
                    }
                }
                .navigationTitle("New Group")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") {
                            Task { await create() }
                        }
                        .disabled(!draft.problems().isEmpty || isCreating)
                    }
                }
            }
        }

        private func binding(forProfile profile: String) -> Binding<Bool> {
            Binding(
                get: { chosenProfiles.contains(profile) },
                set: { isOn in
                    if isOn {
                        chosenProfiles.insert(profile)
                    } else {
                        chosenProfiles.remove(profile)
                    }
                })
        }

        private func create() async {
            isCreating = true
            defer { isCreating = false }
            do {
                _ = try await model.create(draft, roomID: roomID)
                dismiss()
            } catch {
                errorMessage = RoomFailure.message(for: error)
            }
        }
    }
#endif
