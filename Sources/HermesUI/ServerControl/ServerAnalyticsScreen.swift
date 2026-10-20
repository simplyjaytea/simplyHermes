#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// Tools > Usage: totals and per-model rows for 7, 30 or 90 days (WP-54).
    public struct ServerAnalyticsScreen: View {
        @State private var model: ServerAnalyticsModel
        @State private var window: ServerAnalyticsWindow = .month

        public init(connections: ConnectionsModel) {
            _model = State(initialValue: ServerAnalyticsModel(connections: connections))
        }

        init(model: ServerAnalyticsModel) {
            _model = State(initialValue: model)
        }

        public var body: some View {
            List {
                Section {
                    Picker("Period", selection: $window) {
                        ForEach(ServerAnalyticsWindow.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("serverAnalytics.window")
                }
                if let errorText = model.errorText {
                    Section {
                        ServerControlProblem(text: errorText)
                    }
                }
                if !model.totals.isEmpty {
                    Section("Totals") {
                        ServerStatsRowsView(rows: model.totals)
                    }
                    .accessibilityIdentifier("serverAnalytics.totals")
                }
                ForEach(model.groups) { group in
                    Section(group.title) {
                        ServerStatsRowsView(rows: group.rows)
                    }
                }
            }
            .navigationTitle("Usage")
            .refreshable { await model.load(window) }
            .task(id: window) { await model.load(window) }
            .overlay {
                if model.totals.isEmpty && model.groups.isEmpty && model.errorText == nil && !model.isLoading {
                    ContentUnavailableView(
                        "No usage yet", systemImage: "chart.bar.xaxis",
                        description: Text("Usage shows up here once the server has answered."))
                }
            }
        }
    }

    #Preview("Usage, outer", traits: .fixedLayout(width: 466, height: 678)) {
        NavigationStack {
            ServerAnalyticsScreen(model: .preview())
        }
    }

    #Preview("Usage, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        NavigationStack {
            ServerAnalyticsScreen(model: .preview())
        }
    }

    #Preview("Usage, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        NavigationStack {
            ServerAnalyticsScreen(model: .preview())
        }
    }

    #Preview("Usage, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        NavigationStack {
            ServerAnalyticsScreen(model: .preview(errorText: "The server did not answer."))
        }
    }
#endif
