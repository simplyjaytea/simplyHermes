#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// Bot settings (WP-41), opened from the profile switcher: the "Applies to" choice, and export of the bot
    /// it points at.
    public struct BotSettingsSheet: View {
        private let profiles: ProfilesModel
        @State private var model: BotSettingsModel
        @State private var shareFile: ShareFile?
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
                        if BotExport.isOfferedInApp {
                            transferCard
                        }
                        if let problem = model.problem {
                            Text(problem)
                                .font(HermesFont.footnote)
                                .foregroundStyle(HermesColor.destructive)
                                .accessibilityIdentifier("botSettings.problem")
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
                .sheet(item: $shareFile) { file in
                    ActivitySheet(items: [file.url])
                }
            }
        }

        private var transferCard: some View {
            HermesCard {
                Text("Export")
                    .font(HermesFont.headline)
                    .accessibilityAddTraits(.isHeader)
                Text("Export saves this bot as an archive you can keep or share.")
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
            }
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
