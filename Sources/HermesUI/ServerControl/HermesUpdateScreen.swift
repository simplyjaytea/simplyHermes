#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// Settings > Server > Hermes update: the check, the update behind a confirm, progress while it runs, then the
    /// version check and the receipt (WP-54). Installs that cannot be updated from the app show the command to run.
    public struct HermesUpdateScreen: View {
        @State private var model: HermesUpdateModel
        @State private var confirming = false

        public init(connections: ConnectionsModel) {
            _model = State(initialValue: HermesUpdateModel(connections: connections))
        }

        init(model: HermesUpdateModel) {
            _model = State(initialValue: model)
        }

        public var body: some View {
            List {
                if let check = model.check {
                    installedSection(check)
                    if check.updateAvailable == true {
                        updateSection(check)
                    } else if let message = check.message {
                        Section {
                            ServerControlProblem(text: message)
                        }
                    }
                }
                phaseSection
            }
            .navigationTitle("Hermes update")
            .refreshable { await model.loadCheck(force: true) }
            .task { await model.loadCheck(force: false) }
            .confirmationDialog(dialogTitle, isPresented: $confirming, titleVisibility: .visible) {
                Button("Update Hermes", role: .destructive) {
                    Task { await model.startUpdate() }
                }
            } message: {
                Text("The server restarts during the update. The app waits for the new receipt, up to 15 minutes.")
            }
        }

        /// Names the server the update goes to, so the dialog says which server restarts.
        private var dialogTitle: String {
            model.targetName.map { "Update Hermes on \($0)?" } ?? "Update Hermes?"
        }

        private func installedSection(_ check: HermesUpdateCheck) -> some View {
            Section("Installed") {
                LabeledContent("Install") {
                    Text(check.installMethod ?? "Unknown")
                }
                LabeledContent("Version") {
                    Text(check.currentVersion ?? "—")
                }
                LabeledContent("Status") {
                    Text(statusText(check))
                }
            }
            .accessibilityIdentifier("hermesUpdate.installed")
        }

        @ViewBuilder
        private func updateSection(_ check: HermesUpdateCheck) -> some View {
            if check.canApply == true {
                Section {
                    Button("Update Hermes…") {
                        confirming = true
                    }
                    .buttonStyle(HermesButtonStyle(.primary))
                    .disabled(model.isBusy)
                    .accessibilityIdentifier("hermesUpdate.start")
                } footer: {
                    Text(check.message ?? "The server restarts during the update.")
                }
            } else {
                Section {
                    Text(check.updateCommand ?? "Update Hermes on the server.")
                        .font(HermesFont.code)
                        .textSelection(.enabled)
                } header: {
                    Text("Update by hand")
                } footer: {
                    Text(check.message ?? "This install cannot be updated from the app.")
                }
            }
        }

        @ViewBuilder
        private var phaseSection: some View {
            switch model.phase {
            case .idle:
                EmptyView()
            case .checking:
                Section {
                    ServerControlBusyLine(text: "Checking for updates…")
                }
            case .updating:
                Section {
                    ServerControlBusyLine(text: "Updating Hermes. The server may restart; this can take a few minutes.")
                        .accessibilityIdentifier("hermesUpdate.progress")
                }
            case .finished:
                Section("Result") {
                    if let versionText = model.versionText {
                        Text(versionText)
                    }
                    ServerStatsRowsView(rows: model.receiptRows)
                }
                .accessibilityIdentifier("hermesUpdate.result")
            case .timedOut:
                Section {
                    ServerControlProblem(text: "The update did not finish within 15 minutes. Check the server.")
                }
            case .failed(let text):
                Section {
                    ServerControlProblem(text: text)
                }
            }
        }

        private func statusText(_ check: HermesUpdateCheck) -> String {
            if check.updateAvailable == true {
                if let behind = check.behind, behind > 0 { return "\(behind) commits behind" }
                return "Update available"
            }
            if check.isUpToDate { return "Up to date" }
            return "Unknown"
        }
    }

    #Preview("Hermes update, outer", traits: .fixedLayout(width: 466, height: 678)) {
        NavigationStack {
            HermesUpdateScreen(model: .preview(check: .sampleAvailable))
        }
    }

    #Preview("Hermes update, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        NavigationStack {
            HermesUpdateScreen(model: .preview(check: .sampleAvailable))
        }
    }

    #Preview("Hermes update, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        NavigationStack {
            HermesUpdateScreen(model: .preview(check: .sampleAvailable, phase: .updating))
        }
    }

    #Preview("Hermes update, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        NavigationStack {
            HermesUpdateScreen(model: .preview(check: nil, phase: .failed("The server did not answer.")))
        }
    }
#endif
