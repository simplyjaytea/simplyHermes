#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// The nodes as a list, newest first (WP-52). A tap on a row opens the node's sheet. Pull down to load again.
    ///
    /// Each row reads as one line to VoiceOver: the name, what kind of node it is, the facts and the date.
    struct JourneyListView: View {
        let model: MemoryJourneyModel

        var body: some View {
            List {
                ForEach(model.board.rows) { node in
                    Button {
                        model.openNode(node.id)
                    } label: {
                        JourneyRow(node: node)
                    }
                    .tint(HermesColor.primaryText)
                    .accessibilityLabel(node.spokenSummary)
                    .accessibilityHint("Opens the details")
                    .accessibilityIdentifier("memory.row.\(node.id)")
                }
            }
            .accessibilityIdentifier("memory.list")
            .listStyle(.plain)
            .refreshable { await model.refresh() }
            .overlay { JourneyStatusView(model: model, shownCount: model.board.filteredCount) }
            .safeAreaInset(edge: .top, spacing: 0) {
                if !model.board.isEmpty { JourneyFilterBar(model: model) }
            }
        }
    }

    /// One row of the list: a mark in the node's colour, its name, its facts and when it was last touched.
    struct JourneyRow: View {
        let node: JourneyNode

        var body: some View {
            HStack(spacing: 12) {
                JourneyGlyph(node: node)
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.label)
                        .font(HermesFont.body.weight(.semibold))
                        .lineLimit(2)
                    Text(node.detailParts.joined(separator: " \u{00B7} "))
                        .font(HermesFont.footnote)
                        .foregroundStyle(HermesColor.secondaryText)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                if let date = node.date {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(HermesFont.footnote)
                        .foregroundStyle(HermesColor.secondaryText)
                }
            }
            .padding(.vertical, 2)
        }
    }

    /// The mark of a node in the list. It uses the shapes and colours of the graph: a rounded square for a memory chunk,
    /// a circle for a skill, a ring for a skill the agent wrote itself, a white dot for a pinned one, and a fainter mark
    /// for an archived or stale one.
    struct JourneyGlyph: View {
        let node: JourneyNode

        private static let side: CGFloat = 16

        private var shape: AnyShape {
            node.kind == .memory ? AnyShape(RoundedRectangle(cornerRadius: Self.side * 0.3)) : AnyShape(Circle())
        }

        var body: some View {
            let color = JourneyPalette.color(for: node)
            ZStack {
                shape
                    .fill(color.opacity(node.isDimmed ? 0.4 : 1))
                    .frame(width: Self.side, height: Self.side)
                if node.isLearned {
                    shape
                        .stroke(color.opacity(0.75), lineWidth: 1.5)
                        .frame(width: Self.side + 7, height: Self.side + 7)
                }
                if node.pinned {
                    Circle()
                        .fill(HermesColor.onAccent.opacity(0.9))
                        .frame(width: Self.side * 0.35, height: Self.side * 0.35)
                }
            }
            .frame(width: Self.side + 8, height: Self.side + 8)
            .accessibilityHidden(true)
        }
    }
#endif
