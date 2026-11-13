#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// Settings > Bots screen: lists bots for editing and hosts bot runtime settings (Keep bots live).
    public struct SettingsBotsScreen: View {
        private let connections: ConnectionsModel
        @State private var model: BotsModel
        @State private var editingEntry: BotRosterEntry?

        public init(connections: ConnectionsModel) {
            self.connections = connections
            _model = State(initialValue: BotsModel(connections: connections))
        }

        public var body: some View {
            List {
                Section("Bots") {
                    if model.isLoading && model.entries.isEmpty {
                        ProgressView("Loading bots…")
                    } else if model.entries.isEmpty {
                        Text("No bots found on the active server.")
                            .foregroundStyle(HermesColor.secondaryText)
                    } else {
                        ForEach(model.entries) { entry in
                            Button {
                                editingEntry = entry
                            } label: {
                                HStack(spacing: 12) {
                                    BotAvatarView(name: entry.title, avatar: entry.avatar, tint: entry.tint)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.title)
                                            .font(HermesFont.headline)
                                            .foregroundStyle(HermesColor.primaryText)
                                        Text("@\(entry.handle)")
                                            .font(HermesFont.footnote)
                                            .foregroundStyle(HermesColor.secondaryText)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(HermesFont.footnote)
                                        .foregroundStyle(HermesColor.secondaryText)
                                        .accessibilityHidden(true)
                                }
                            }
                            .accessibilityIdentifier("settings.bots.\(entry.profile)")
                        }
                    }
                }

                BotsSettingsSection()
            }
            .navigationTitle("Bots")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await model.reload()
            }
            .sheet(item: $editingEntry) { entry in
                BotSettingsScreen(entry: entry, connections: connections, rosterModel: model)
            }
        }
    }
#endif
