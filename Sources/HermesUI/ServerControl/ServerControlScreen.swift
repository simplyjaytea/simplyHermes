#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// Settings > Server > Gateway: the gateway's state, and start, stop, restart and drain, each behind a confirm
    /// dialog. Stop and restart show "Reconnecting…" while the server is away (WP-54).
    public struct ServerControlScreen: View {
        @State private var model: ServerControlModel
        @State private var pending: ServerControlAction?

        public init(connections: ConnectionsModel) {
            _model = State(initialValue: ServerControlModel(connections: connections))
        }

        init(model: ServerControlModel) {
            _model = State(initialValue: model)
        }

        public var body: some View {
            List {
                if let errorText = model.errorText {
                    Section {
                        ServerControlProblem(text: errorText)
                    }
                }
                if let status = model.status {
                    statusSection(status)
                }
                actionSection
                if case .working(let action) = model.phase {
                    Section {
                        ServerControlBusyLine(text: action.waitsForServer ? "Reconnecting…" : "Sending…")
                            .accessibilityIdentifier("serverControl.busy")
                    }
                }
                resultSection
                if !model.idleRows.isEmpty {
                    Section("Idle check") {
                        ServerStatsRowsView(rows: model.idleRows)
                    }
                }
            }
            .navigationTitle("Gateway")
            .refreshable { await model.load() }
            .task { await model.load() }
            .overlay {
                if model.status == nil && model.errorText == nil && model.isLoading {
                    ProgressView()
                }
            }
            .confirmationDialog(
                pending.map { dialogTitle(for: $0) } ?? "",
                isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                titleVisibility: .visible, presenting: pending
            ) { action in
                Button(ServerControlModel.title(for: action), role: role(for: action)) {
                    Task { await model.perform(action) }
                }
            } message: { action in
                Text(detail(for: action))
            }
        }

        private func statusSection(_ status: ServerControlStatus) -> some View {
            Section("Status") {
                LabeledContent("State") {
                    Text(status.gateway.gatewayState ?? "Unknown")
                }
                LabeledContent("Running") {
                    Text(yesNo(status.server.gatewayRunning))
                }
                LabeledContent("Mode") {
                    Text(status.gateway.gatewayMode ?? "—")
                }
                LabeledContent("Busy") {
                    Text(yesNo(status.gateway.gatewayBusy))
                }
                LabeledContent("Can drain") {
                    Text(yesNo(status.gateway.gatewayDrainable))
                }
                if let reason = status.gateway.gatewayExitReason {
                    LabeledContent("Last exit") {
                        Text(reason)
                    }
                }
                LabeledContent("Overall") {
                    Text(status.server.overall ?? "—")
                }
            }
            .accessibilityIdentifier("serverControl.status")
        }

        private var actionSection: some View {
            Section {
                ForEach(ServerControlAction.allCases, id: \.self) { action in
                    Button(ServerControlModel.title(for: action)) {
                        pending = action
                    }
                    .buttonStyle(HermesButtonStyle(kind(for: action)))
                    .disabled(model.isBusy)
                    .accessibilityIdentifier("serverControl.\(action.rawValue)")
                }
            } footer: {
                Text("Every action asks first. Stop and restart wait up to 60 seconds for the server to answer.")
            }
        }

        @ViewBuilder
        private var resultSection: some View {
            switch model.phase {
            case .done(let text):
                Section {
                    Text(text)
                        .accessibilityIdentifier("serverControl.result")
                }
            case .failed(let text):
                Section {
                    ServerControlProblem(text: text)
                }
            case .idle, .working:
                EmptyView()
            }
        }

        /// The action and the server it goes to, so the dialog says which server the action reaches.
        private func dialogTitle(for action: ServerControlAction) -> String {
            guard let name = model.targetName else { return ServerControlModel.title(for: action) }
            return "\(ServerControlModel.title(for: action)) on \(name)"
        }

        private func kind(for action: ServerControlAction) -> HermesButtonStyle.Kind {
            role(for: action) == .destructive ? .destructive : .tinted
        }

        private func role(for action: ServerControlAction) -> ButtonRole? {
            switch action {
            case .stop, .restart: return .destructive
            case .start, .drain, .cancelDrain: return nil
            }
        }

        private func detail(for action: ServerControlAction) -> String {
            switch action {
            case .start: return "The gateway starts on the server."
            case .stop: return "Messages stop reaching Hermes until the gateway starts again."
            case .restart:
                return "The gateway restarts. The app reconnects when the server is back, for up to 60 seconds."
            case .drain:
                return "The gateway works through what it has and takes no new work. Cancel the drain to resume."
            case .cancelDrain: return "The gateway goes back to normal work."
            }
        }

        private func yesNo(_ flag: Bool?) -> String {
            guard let flag else { return "Unknown" }
            return flag ? "Yes" : "No"
        }
    }

    #Preview("Gateway, outer", traits: .fixedLayout(width: 466, height: 678)) {
        NavigationStack {
            ServerControlScreen(model: .preview(status: ServerControlStatus.sample))
        }
    }

    #Preview("Gateway, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        NavigationStack {
            ServerControlScreen(model: .preview(status: ServerControlStatus.sample))
        }
    }

    #Preview("Gateway, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        NavigationStack {
            ServerControlScreen(model: .preview(status: ServerControlStatus.sample, phase: .working(.restart)))
        }
    }

    #Preview("Gateway, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        NavigationStack {
            ServerControlScreen(model: .preview(status: nil, errorText: "The server did not answer."))
        }
    }
#endif
