#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// The All, Used and Learned chips, each with the number of nodes it shows.
    struct JourneyFilterBar: View {
        let model: MemoryJourneyModel

        var body: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(JourneyFilter.allCases) { filter in
                        let count = model.board.count(filter)
                        let noun = count == 1 ? "node" : "nodes"
                        HermesChip("\(filter.title) \(count)", isSelected: model.board.filter == filter) {
                            model.setFilter(filter)
                        }
                        .accessibilityLabel("\(filter.title), \(count) \(noun)")
                        .accessibilityIdentifier("memory.filter.\(filter.rawValue)")
                    }
                }
                .padding(.horizontal, 16)
            }
            .background(.bar)
        }
    }

    /// The timeline at the bottom of the graph. Drag the slider back to see the graph as it was: nodes that did not
    /// exist yet drop out. With no real dates in the graph the slider steps through the nodes, oldest first.
    struct JourneyScrubber: View {
        let model: MemoryJourneyModel

        var body: some View {
            let board = model.board
            if board.graph.nodes.count > 1 {
                VStack(spacing: 2) {
                    HStack {
                        Text(heading(of: board))
                        Spacer(minLength: 8)
                        Text("\(board.visibleCount) of \(board.filteredCount)")
                    }
                    .font(HermesFont.caption)
                    .foregroundStyle(HermesColor.secondaryText)
                    Slider(value: Binding(get: { model.board.scrub }, set: { model.setScrub($0) }), in: 0...1)
                        .accessibilityLabel("Timeline")
                        .accessibilityValue(
                            "\(heading(of: board)), \(board.visibleCount) of \(board.filteredCount) nodes"
                        )
                        .accessibilityIdentifier("memory.scrubber")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.bar)
            }
        }

        /// Where the slider stands: a date, "Everything" at the end, or "Oldest first" when the graph has no dates.
        private func heading(of board: JourneyBoard) -> String {
            guard board.scrub < 1 else { return "Everything" }
            guard let date = board.scrubDate else { return "Oldest first" }
            return "Up to \(date.formatted(date: .abbreviated, time: .omitted))"
        }
    }
#endif
