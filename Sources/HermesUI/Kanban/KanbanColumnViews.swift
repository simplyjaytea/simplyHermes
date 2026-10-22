#if canImport(UIKit)
    import Foundation
    import HermesKit
    import SwiftUI

    /// One column of the board as one page (Q40). Cards keep the server's order.
    struct KanbanColumnPage: View {
        let column: KanbanColumn
        let onOpen: (KanbanCard) -> Void

        var body: some View {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Text(column.name.capitalized)
                            .font(HermesFont.headline)
                        Text("\(column.cards.count)")
                            .font(HermesFont.subheadline)
                            .foregroundStyle(HermesColor.secondaryText)
                            .accessibilityLabel(Text("\(column.cards.count) tasks"))
                    }
                    .padding(.horizontal, 4)
                    if column.cards.isEmpty {
                        Text("No tasks in this column.")
                            .font(HermesFont.footnote)
                            .foregroundStyle(HermesColor.secondaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                    ForEach(column.cards) { card in
                        Button {
                            onOpen(card)
                        } label: {
                            KanbanTaskCard(card: card)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(HermesColor.groupedBackground)
            .accessibilityIdentifier("kanban.column.\(column.name)")
        }
    }

    /// A card on a board: its title. The assignee and priority show in the task sheet.
    struct KanbanTaskCard: View {
        let card: KanbanCard

        var body: some View {
            HermesCard {
                Text(card.title ?? card.id)
                    .font(HermesFont.body.weight(.semibold))
                    .multilineTextAlignment(.leading)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("kanban.task.\(card.id)")
        }
    }

    #Preview("Column, outer", traits: .fixedLayout(width: 466, height: 678)) {
        if let column = KanbanSampleData.readyColumn { KanbanColumnPage(column: column, onOpen: { _ in }) }
    }

    #Preview("Column, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        if let column = KanbanSampleData.readyColumn { KanbanColumnPage(column: column, onOpen: { _ in }) }
    }

    #Preview("Column, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        if let column = KanbanSampleData.readyColumn { KanbanColumnPage(column: column, onOpen: { _ in }) }
    }

    #Preview("Column, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        if let column = KanbanSampleData.readyColumn { KanbanColumnPage(column: column, onOpen: { _ in }) }
    }
#endif
