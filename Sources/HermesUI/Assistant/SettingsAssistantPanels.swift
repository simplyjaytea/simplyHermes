#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// The error or confirmation line at the top of an assistant page.
    struct SettingsAssistantStatus: View {
        @Environment(\.hermesPalette) private var palette
        let model: SettingsAssistantModel

        var body: some View {
            if let errorText = model.errorText {
                Label(errorText, systemImage: "wifi.slash")
                    .font(HermesFont.footnote)
                    .foregroundStyle(palette.secondaryText)
                    .accessibilityIdentifier("assistant.error")
                    .hermesListRows()
            } else if let noticeText = model.noticeText {
                Label(noticeText, systemImage: "checkmark.circle")
                    .font(HermesFont.footnote)
                    .foregroundStyle(palette.secondaryText)
                    .accessibilityIdentifier("assistant.notice")
                    .hermesListRows()
            }
        }
    }

    /// One panel of an assistant page as a section. Values that look like secrets stay masked until the user taps Show.
    struct SettingsAssistantPanelSection: View {
        @Environment(\.hermesPalette) private var palette
        let panel: SettingsAssistantPanel
        @State private var revealed: Set<[String]> = []

        var body: some View {
            Section {
                if let errorText = panel.errorText {
                    Label(errorText, systemImage: "exclamationmark.circle")
                        .font(HermesFont.footnote)
                        .foregroundStyle(palette.secondaryText)
                } else if !panel.isLoaded {
                    ProgressView()
                } else if panel.rows.isEmpty {
                    Text("The server sent no values.")
                        .foregroundStyle(palette.secondaryText)
                } else {
                    ForEach(panel.rows) { row in
                        LabeledContent {
                            value(of: row)
                        } label: {
                            Text(row.label.isEmpty ? "Value" : row.label)
                                .font(HermesFont.codeSmall)
                        }
                    }
                }
            } header: {
                Text(panel.title)
            } footer: {
                if let footer = panel.footer {
                    Text(footer)
                }
            }
            .hermesListRows()
        }

        @ViewBuilder
        private func value(of row: SettingsAssistantRow) -> some View {
            if row.isSecret && !revealed.contains(row.id) {
                HStack(spacing: 12) {
                    Text("••••••••")
                        .foregroundStyle(palette.secondaryText)
                    Button("Show") { reveal(row.id) }
                        .accessibilityLabel(Text("Show \(row.label)"))
                }
            } else {
                HStack(spacing: 12) {
                    Text(row.value)
                    if row.isSecret {
                        Button("Hide") { hide(row.id) }
                            .accessibilityLabel(Text("Hide \(row.label)"))
                    }
                }
            }
        }

        private func reveal(_ id: [String]) {
            revealed.insert(id)
        }

        private func hide(_ id: [String]) {
            revealed.remove(id)
        }
    }

    extension View {
        /// Reads the page's answers when it appears, and again on pull to refresh.
        func settingsAssistantLoads(_ model: SettingsAssistantModel) -> some View {
            task { await model.load() }
                .refreshable { await model.load() }
        }
    }
#endif
