#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// Settings > Server > Update all servers: the check of every saved server, one at a time. A server with an update
    /// asks first, by name, with Update, Skip and Stop. Each server gets a line in the result list (WP-54).
    /// ConnectionsModel keeps the run, so reopening this screen shows a run that is still going.
    public struct FleetUpdateScreen: View {
        @State private var model: FleetUpdateModel

        public init(connections: ConnectionsModel) {
            _model = State(initialValue: connections.fleetUpdate)
        }

        init(model: FleetUpdateModel) {
            _model = State(initialValue: model)
        }

        public var body: some View {
            List {
                Section {
                    Button("Update all servers…") {
                        model.start()
                    }
                    .buttonStyle(HermesButtonStyle(.primary))
                    .disabled(model.isBusy || model.servers.isEmpty)
                    .accessibilityIdentifier("fleetUpdate.start")
                } footer: {
                    Text("Each saved server is checked. You confirm each update before it runs. One server at a time.")
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
            .confirmationDialog(
                model.question.map { "Update Hermes on \($0.server.name)?" } ?? "",
                isPresented: Binding(get: { model.question != nil }, set: { if !$0 { model.dismissQuestion() } }),
                titleVisibility: .visible, presenting: model.question
            ) { _ in
                Button("Update", role: .destructive) { model.answer(.update) }
                Button("Skip") { model.answer(.skip) }
                Button("Stop", role: .cancel) { model.answer(.stop) }
            } message: { question in
                let version = question.check.currentVersion ?? "Current version unknown"
                Text("\(version), update available. The server restarts.")
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
