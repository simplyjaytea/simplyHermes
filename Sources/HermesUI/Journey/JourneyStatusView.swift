#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// What stands in place of the list or the graph when there is nothing to draw: no server, a first load under way,
    /// a failed load, a graph with no nodes, or a filter that hides every node.
    struct JourneyStatusView: View {
        let model: MemoryJourneyModel
        /// How many nodes the screen shows now. Zero with a graph that has nodes means the filter hides them all.
        let shownCount: Int

        var body: some View {
            switch model.phase {
            case .notConnected:
                ContentUnavailableView(
                    "No server connected", systemImage: "server.rack",
                    description: Text("Connect a server in Settings to see what Hermes has learned.")
                )
                .accessibilityIdentifier("memory.empty")
            case .loading:
                ProgressView("Loading\u{2026}")
                    .accessibilityIdentifier("memory.loading")
            case .failed(let reason):
                failed(reason)
            case .loaded:
                loaded
            }
        }

        private func failed(_ reason: String) -> some View {
            ContentUnavailableView {
                Label("Could not load the memory graph", systemImage: "exclamationmark.triangle")
            } description: {
                Text(reason)
            } actions: {
                Button("Try again") { Task { await model.refresh() } }
                    .buttonStyle(HermesButtonStyle(.primary, fillsWidth: false))
                    .accessibilityIdentifier("memory.retry")
            }
            .accessibilityIdentifier("memory.failed")
        }

        @ViewBuilder
        private var loaded: some View {
            if model.board.isEmpty {
                ContentUnavailableView(
                    "Nothing learned yet", systemImage: "brain",
                    description: Text("Skills Hermes learns and memories it keeps show up here.")
                )
                .accessibilityIdentifier("memory.empty")
            } else if shownCount == 0 {
                if model.board.filteredCount == 0 { noMatches } else { beforeTheStart }
            }
        }

        /// The chosen filter hides every node.
        private var noMatches: some View {
            ContentUnavailableView {
                Label(
                    "Nothing under \u{201C}\(model.board.filter.title)\u{201D}",
                    systemImage: "line.3.horizontal.decrease")
            } description: {
                Text("Switch to All to see every node.")
            } actions: {
                Button("Show all") { model.setFilter(.all) }
                    .buttonStyle(HermesButtonStyle(.tinted, fillsWidth: false))
                    .accessibilityIdentifier("memory.showAll")
            }
            .accessibilityIdentifier("memory.noMatches")
        }

        /// The timeline stands before the first node that passes the filter.
        private var beforeTheStart: some View {
            ContentUnavailableView {
                Label("Nothing yet at this point", systemImage: "clock.arrow.circlepath")
            } description: {
                Text("Drag the timeline forward to see the nodes that came later.")
            } actions: {
                Button("Show everything") { model.setScrub(1) }
                    .buttonStyle(HermesButtonStyle(.tinted, fillsWidth: false))
                    .accessibilityIdentifier("memory.showEverything")
            }
            .accessibilityIdentifier("memory.beforeStart")
        }
    }
#endif
