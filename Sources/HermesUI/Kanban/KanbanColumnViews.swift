#if canImport(UIKit)
    import Foundation
    import HermesKit
    import SwiftUI

    /// One column of the board as one page (Q40). Cards keep the server's order.
    struct KanbanColumnPage: View {
        let column: KanbanColumn
        let onOpen: (KanbanTask) -> Void

        var body: some View {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Text(column.name.capitalized)
                            .font(HermesFont.headline)
                        Text("\(column.tasks.count)")
                            .font(HermesFont.subheadline)
                            .foregroundStyle(HermesColor.secondaryText)
                            .accessibilityLabel(Text("\(column.tasks.count) tasks"))
                    }
                    .padding(.horizontal, 4)
                    if column.tasks.isEmpty {
                        Text("No tasks in this column.")
                            .font(HermesFont.footnote)
                            .foregroundStyle(HermesColor.secondaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                    ForEach(column.tasks) { task in
                        Button {
                            onOpen(task)
                        } label: {
                            KanbanTaskCard(task: task)
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

    /// A task on a board: title, assignee and priority.
    struct KanbanTaskCard: View {
        let task: KanbanTask

        var body: some View {
            HermesCard {
                Text(task.title)
                    .font(HermesFont.body.weight(.semibold))
                    .multilineTextAlignment(.leading)
                HStack(spacing: 8) {
                    Label(task.assignee ?? "Unassigned", systemImage: "person.crop.circle")
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("Priority \(task.priority ?? 0)")
                }
                .font(HermesFont.footnote)
                .foregroundStyle(HermesColor.secondaryText)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("kanban.task.\(task.id)")
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
