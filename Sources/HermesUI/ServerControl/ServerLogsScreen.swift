#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// Tools > Logs: log lines with a level or file filter and search, pull to refresh, and a system stats header
    /// (WP-54). Filters reload after a short pause, so typing does not send a request per letter.
    public struct ServerLogsScreen: View {
        @State private var model: ServerLogsModel
        @State private var file = "agent"
        @State private var level: ServerLogsLevel = .all
        @State private var search = ""

        public init(connections: ConnectionsModel) {
            _model = State(initialValue: ServerLogsModel(connections: connections))
        }

        init(model: ServerLogsModel) {
            _model = State(initialValue: model)
        }

        private var filter: ServerLogsFilter {
            ServerLogsFilter(file: file, level: level, search: search)
        }

        public var body: some View {
            List {
                if !model.stats.isEmpty {
                    Section("System") {
                        ServerStatsRowsView(rows: model.stats)
                    }
                    .accessibilityIdentifier("serverLogs.stats")
                }
                Section("Filter") {
                    Picker("Level", selection: $level) {
                        ForEach(ServerLogsLevel.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .accessibilityIdentifier("serverLogs.level")
                    TextField("Log file", text: $file)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("serverLogs.file")
                }
                Section("Lines") {
                    if let errorText = model.errorText {
                        ServerControlProblem(text: errorText)
                    }
                    ForEach(Array(model.lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(HermesFont.codeSmall)
                            .textSelection(.enabled)
                    }
                }
            }
            .searchable(text: $search, prompt: "Search logs")
            .navigationTitle("Logs")
            .refreshable { await model.load(filter) }
            .task(id: filter) {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                await model.load(filter)
            }
            .overlay {
                if model.lines.isEmpty && model.errorText == nil && !model.isLoading {
                    ContentUnavailableView(
                        "No log lines", systemImage: "doc.text.magnifyingglass",
                        description: Text("Change the filter or pull to refresh."))
                }
            }
        }
    }

    #Preview("Logs, outer", traits: .fixedLayout(width: 466, height: 678)) {
        NavigationStack {
            ServerLogsScreen(model: .preview(lines: ServerLogsModel.sampleLines))
        }
    }

    #Preview("Logs, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        NavigationStack {
            ServerLogsScreen(model: .preview(lines: ServerLogsModel.sampleLines))
        }
    }

    #Preview("Logs, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        NavigationStack {
            ServerLogsScreen(model: .preview(lines: ServerLogsModel.sampleLines))
        }
    }

    #Preview("Logs, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        NavigationStack {
            ServerLogsScreen(model: .preview(lines: [], errorText: "The server did not answer."))
        }
    }
#endif
