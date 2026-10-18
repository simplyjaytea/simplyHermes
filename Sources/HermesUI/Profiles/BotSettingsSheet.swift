#if canImport(UIKit)
    import HermesKit
    import SwiftUI
    import UniformTypeIdentifiers

    /// Bot settings (WP-41), opened from the profile switcher: the "Applies to" choice, the facts of the bot it points at,
    /// and export and import of that bot's profile. Editing the description and the model comes later.
    public struct BotSettingsSheet: View {
        private let profiles: ProfilesModel
        @State private var model: BotSettingsModel
        @State private var shareFile: ShareFile?
        @State private var showsImporter = false
        @Environment(\.dismiss) private var dismiss

        /// Creates the sheet over the profiles and servers the app already holds.
        public init(profiles: ProfilesModel, connections: ConnectionsModel) {
            self.profiles = profiles
            _model = State(initialValue: BotSettingsModel(profiles: profiles, connections: connections))
        }

        public var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        AppliesToSelector(
                            choice: profiles.appliesTo, profiles: profiles.selection.profiles,
                            active: profiles.selection.current?.name
                        ) { choice in
                            profiles.setAppliesTo(choice)
                        }
                        factsCard
                        transferCard
                        if let problem = model.problem {
                            Text(problem)
                                .font(HermesFont.footnote)
                                .foregroundStyle(HermesColor.destructive)
                                .accessibilityIdentifier("botSettings.problem")
                        }
                        if let notice = model.notice {
                            Text(notice)
                                .font(HermesFont.footnote)
                                .foregroundStyle(HermesColor.secondaryText)
                                .accessibilityIdentifier("botSettings.notice")
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(HermesColor.groupedBackground)
                .navigationTitle("Bot settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .task { await model.load() }
                .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.data]) { result in
                    guard case .success(let urls) = result, let url = urls.first else { return }
                    Task { await model.importArchive(from: url) }
                }
                .sheet(item: $shareFile) { file in
                    ActivitySheet(items: [file.url])
                }
            }
        }

        private var factsCard: some View {
            HermesCard {
                if let facts = model.facts {
                    Text(facts.title)
                        .font(HermesFont.headline)
                        .accessibilityAddTraits(.isHeader)
                    factRow("Name", facts.name)
                    factRow("Model", facts.model ?? "Not set")
                    factRow("Provider", facts.provider ?? "Not set")
                    factRow("Skills", "\(facts.skillCount)")
                    factRow("Last session", lastSessionText(facts))
                } else if model.isWorking {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Loading bot details")
                } else {
                    Text("Bot details appear once the server answers.")
                        .font(HermesFont.footnote)
                        .foregroundStyle(HermesColor.secondaryText)
                }
            }
            .accessibilityIdentifier("botSettings.facts")
        }

        private var transferCard: some View {
            HermesCard {
                Text("Export and import")
                    .font(HermesFont.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(
                    "An export holds the bot's skills, memory, persona, cron jobs, plugins and settings. "
                        + "API keys are left out."
                )
                .font(HermesFont.footnote)
                .foregroundStyle(HermesColor.secondaryText)
                Button {
                    Task {
                        if let url = await model.exportTarget() { shareFile = ShareFile(url: url) }
                    }
                } label: {
                    Label("Export this bot", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(HermesButtonStyle(.primary))
                .disabled(model.target == nil || model.isWorking)
                .accessibilityIdentifier("botSettings.export")
                Button {
                    showsImporter = true
                } label: {
                    Label("Import a bot", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(HermesButtonStyle(.tinted))
                .disabled(model.isWorking)
                .accessibilityHint("Creates a new bot from an exported archive")
                .accessibilityIdentifier("botSettings.import")
            }
        }

        private func factRow(_ label: String, _ value: String) -> some View {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .foregroundStyle(HermesColor.secondaryText)
                Spacer(minLength: 12)
                Text(value)
                    .multilineTextAlignment(.trailing)
            }
            .font(HermesFont.subheadline)
            .accessibilityElement(children: .combine)
        }

        private func lastSessionText(_ facts: BotFacts) -> String {
            guard let session = facts.lastSession else { return "None yet" }
            let title = session.title.isEmpty ? "Untitled session" : session.title
            guard let date = session.lastActive else { return title }
            return title + ", " + date.formatted(.relative(presentation: .named))
        }
    }

    /// A file for the share sheet. Its URL identifies it.
    struct ShareFile: Identifiable {
        let url: URL
        var id: URL { url }
    }

    /// The system share sheet for `items`.
    struct ActivitySheet: UIViewControllerRepresentable {
        let items: [Any]

        func makeUIViewController(context: Context) -> UIActivityViewController {
            UIActivityViewController(activityItems: items, applicationActivities: nil)
        }

        func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
    }
#endif
