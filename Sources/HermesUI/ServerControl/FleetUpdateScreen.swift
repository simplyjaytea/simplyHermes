#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// Settings > Server > Update all servers: the check and update of every saved server, one at a time, behind a
    /// confirm. Each server gets a line in the result list (WP-54).
    public struct FleetUpdateScreen: View {
        @State private var model: FleetUpdateModel
        @State private var confirming = false

        public init(connections: ConnectionsModel) {
            _model = State(initialValue: FleetUpdateModel(connections: connections))
        }

        init(model: FleetUpdateModel) {
            _model = State(initialValue: model)
        }

        public var body: some View {
            List {
                Section {
                    Button("Update all servers…") {
                        confirming = true
                    }
                    .buttonStyle(HermesButtonStyle(.primary))
                    .disabled(model.isBusy || model.servers.isEmpty)
                    .accessibilityIdentifier("fleetUpdate.start")
                } footer: {
                    Text("Each saved server is checked, then updated if an update exists. One server at a time.")
                }
                if let errorText = model.errorText {
                    Section {
                        ServerControlProblem(text: errorText)
                    }
                }
                progressSection
                if model.entries.isEmpty {
                    serversSection
                } else {
                    resultsSection
                }
            }
            .navigationTitle("Update all servers")
            .confirmationDialog("Update all servers?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Update all servers", role: .destructive) {
                    Task { await model.run() }
                }
            } message: {
                Text("Each saved server is checked and updated in turn. Servers restart during their update.")
            }
        }

        @ViewBuilder
        private var progressSection: some View {
            if case .running(let position, let total, let name) = model.phase {
                Section {
                    ServerControlBusyLine(text: progressText(position: position, total: total, name: name))
                }
                .accessibilityIdentifier("fleetUpdate.progress")
            }
        }

        private var serversSection: some View {
            Section("Servers") {
                if model.servers.isEmpty {
                    Text("Add a server in Settings > Servers.")
                        .foregroundStyle(HermesColor.secondaryText)
                } else {
                    ForEach(model.servers) { server in
                        Text(server.name)
                    }
                }
            }
        }

        private var resultsSection: some View {
            Section("Results") {
                ForEach(model.entries) { entry in
                    resultRow(entry)
                }
            }
            .accessibilityIdentifier("fleetUpdate.results")
        }

        private func resultRow(_ entry: FleetUpdateEntry) -> some View {
            let problem = FleetUpdateModel.isProblem(entry.state)
            return VStack(alignment: .leading, spacing: 2) {
                Text(entry.server.name)
                    .font(HermesFont.body)
                Text(FleetUpdateModel.summary(entry.state))
                    .font(HermesFont.footnote)
                    .foregroundStyle(problem ? HermesColor.destructive : HermesColor.secondaryText)
            }
            .accessibilityElement(children: .combine)
        }

        private func progressText(position: Int, total: Int, name: String?) -> String {
            guard let name else { return "Starting…" }
            return "Server \(position) of \(total): \(name)"
        }
    }

    #Preview("Update all servers, outer", traits: .fixedLayout(width: 466, height: 678)) {
        NavigationStack {
            FleetUpdateScreen(model: .preview())
        }
    }

    #Preview("Update all servers, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        NavigationStack {
            FleetUpdateScreen(model: .preview(entries: FleetUpdateModel.sampleEntries, phase: .finished))
        }
    }

    #Preview("Update all servers, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        NavigationStack {
            FleetUpdateScreen(model: .preview(phase: .running(position: 2, total: 2, name: "Studio Mac")))
        }
    }

    #Preview("Update all servers, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        NavigationStack {
            FleetUpdateScreen(model: .preview(errorText: "Servers are not ready yet. Try again in a moment."))
        }
    }
#endif
