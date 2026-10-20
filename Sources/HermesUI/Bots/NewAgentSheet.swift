#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// New Agent: one sheet, with Advanced collapsed (plan Q34). A name is the only required field.
    struct NewAgentSheet: View {
        let model: BotsModel
        @Environment(\.dismiss) private var dismiss
        @State private var draft = NewAgentDraft()
        @State private var isCreating = false
        @State private var isAdvancedExpanded = false

        var body: some View {
            NavigationStack {
                Form {
                    Section {
                        TextField("Name", text: $draft.name)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("Title (optional)", text: $draft.title)
                        TextField("Role (optional)", text: $draft.roleDescription, axis: .vertical)
                    } footer: {
                        Text(problemMessage ?? handleMessage)
                    }

                    Section("Avatar") {
                        AvatarPicker(
                            avatar: $draft.avatar, name: displayName, tint: BotTint.name(for: draft.profileName))
                    }

                    DisclosureGroup("Advanced", isExpanded: $isAdvancedExpanded) {
                        Picker("Clone from", selection: $draft.cloneFrom) {
                            Text("Nothing (fresh profile)").tag(String?.none)
                            ForEach(model.cloneSources, id: \.self) { name in
                                Text(name).tag(String?.some(name))
                            }
                        }
                        Toggle("Share sign-ins", isOn: $draft.shareAuth)
                        Toggle("Start with no skills", isOn: $draft.noSkills)
                        TextField("Provider", text: $draft.provider)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("Model", text: $draft.model)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("Personality (SOUL)", text: $draft.soul, axis: .vertical)
                            .lineLimit(3...8)
                    }
                }
                .navigationTitle("New Agent")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") { Task { await create() } }
                            .disabled(!canCreate)
                    }
                }
            }
        }

        /// The name the monogram and the title come from.
        private var displayName: String {
            BotNaming.displayName(profile: draft.profileName, title: draft.shownTitle, displayName: nil)
        }

        private var handleMessage: String {
            draft.profileName.isEmpty ? "" : "Handle @\(draft.profileName)"
        }

        /// The first thing that blocks Create, in words.
        private var problemMessage: String? {
            guard let problem = draft.problems(existingProfiles: model.activeProfileNames).first else { return nil }
            switch problem {
            case .nameMissing: return nil
            case .nameInvalid: return "Use letters, digits, - or _, starting with a letter or digit."
            case .nameReserved: return "Hermes reserves that name."
            case .nameTaken: return "A bot named @\(draft.profileName) already exists."
            case .modelIncomplete: return "Set both the provider and the model, or neither."
            }
        }

        private var canCreate: Bool {
            !isCreating && !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && draft.problems(existingProfiles: model.activeProfileNames).isEmpty
        }

        private func create() async {
            isCreating = true
            defer { isCreating = false }
            model.errorMessage = nil
            if await model.createAgent(draft) != nil {
                dismiss()
            }
        }
    }
#endif
