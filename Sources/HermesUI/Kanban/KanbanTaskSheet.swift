#if canImport(UIKit)
    import Foundation
    import HermesKit
    import SwiftUI

    /// The destructive actions that ask first in the task sheet.
    private enum KanbanTaskAction: Hashable {
        case reclaim
        case delete

        var title: String {
            switch self {
            case .reclaim: "Reclaim this task's worker?"
            case .delete: "Delete this task?"
            }
        }

        var buttonTitle: String {
            switch self {
            case .reclaim: "Reclaim worker"
            case .delete: "Delete task"
            }
        }

        var message: String {
            switch self {
            case .reclaim:
                "The running worker is stopped and its claim is released, so the task can be picked up again."
            case .delete: "The task is removed from the board. This can't be undone."
            }
        }
    }

    /// The task sheet (WP-55): status, assignee, priority, description, comments and history, plus the actions on it.
    struct KanbanTaskSheet: View {
        /// The card the board showed. Its title shows until the server's copy of the task loads.
        let card: KanbanCard
        let model: KanbanTaskModel
        let columns: [String]
        let assignees: [String]

        @Environment(\.dismiss) private var dismiss
        @State private var commentText = ""
        @State private var pendingAction: KanbanTaskAction?

        init(card: KanbanCard, model: KanbanTaskModel, columns: [String], assignees: [String]) {
            self.card = card
            self.model = model
            self.columns = columns
            self.assignees = assignees
        }

        private var task: KanbanTask? { model.detail?.task }

        var body: some View {
            NavigationStack {
                List {
                    if let errorText = model.errorText {
                        Section {
                            Label(errorText, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(HermesColor.destructive)
                                .accessibilityIdentifier("kanban.task.error")
                        }
                    }
                    if let notice = model.notice {
                        Section {
                            Label(notice, systemImage: "info.circle")
                                .foregroundStyle(HermesColor.secondaryText)
                        }
                    }
                    summarySection
                    if let description = task?.body, !description.isEmpty {
                        Section("Description") {
                            Text(description)
                        }
                    }
                    commentsSection
                    historySection
                    actionsSection
                }
                .navigationTitle("Task")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
                .task { await model.load() }
                .refreshable { await model.load() }
                .confirmationDialog(
                    pendingAction?.title ?? "", isPresented: pendingBinding, titleVisibility: .visible,
                    presenting: pendingAction
                ) { action in
                    Button(action.buttonTitle, role: .destructive) { perform(action) }
                } message: { action in
                    Text(action.message)
                }
            }
        }

        private var summarySection: some View {
            Section {
                if let task {
                    Text(task.title)
                        .font(HermesFont.headline)
                    LabeledContent("Status", value: task.status.capitalized)
                    LabeledContent("Assignee", value: task.assignee ?? "Unassigned")
                    LabeledContent("Priority", value: "\(task.priority ?? 0)")
                } else {
                    Text(card.title ?? card.id)
                        .font(HermesFont.headline)
                }
            }
        }

        private var commentsSection: some View {
            Section("Comments") {
                HStack(spacing: 8) {
                    TextField("Add a comment", text: $commentText, axis: .vertical)
                        .accessibilityIdentifier("kanban.task.commentField")
                    Button("Send", action: sendComment)
                        .disabled(!canSendComment)
                        .accessibilityIdentifier("kanban.task.send")
                }
            }
        }

        @ViewBuilder
        private var historySection: some View {
            if let events = model.detail?.events, !events.isEmpty {
                Section("History") {
                    ForEach(events) { event in
                        HStack {
                            Text(event.kind)
                            Spacer(minLength: 8)
                            if let time = event.createdAt {
                                Text(Self.eventTime(time))
                                    .font(HermesFont.footnote)
                                    .foregroundStyle(HermesColor.secondaryText)
                            }
                        }
                    }
                }
            }
        }

        private var actionsSection: some View {
            Section("Actions") {
                Menu {
                    ForEach(columns, id: \.self) { column in
                        Button(column.capitalized) { move(to: column) }
                            .disabled(column == task?.status)
                    }
                } label: {
                    Label("Move to column", systemImage: "arrow.right.square")
                }
                .accessibilityIdentifier("kanban.task.move")
                Menu {
                    ForEach(assignees, id: \.self) { profile in
                        Button(profile) { reassign(to: profile) }
                    }
                } label: {
                    Label("Reassign", systemImage: "person.2")
                }
                .disabled(assignees.isEmpty)
                if task?.status == "triage" {
                    Button("Specify with the auxiliary model", systemImage: "wand.and.stars", action: specify)
                }
                if task?.status == "running" {
                    Button("Reclaim worker…", systemImage: "arrow.counterclockwise") { pendingAction = .reclaim }
                }
                Button("Delete task…", systemImage: "trash", role: .destructive) { pendingAction = .delete }
            }
            .disabled(model.isWorking)
        }

        private var canSendComment: Bool {
            !model.isWorking && !commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        private var pendingBinding: Binding<Bool> {
            Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } })
        }

        private func sendComment() {
            let text = commentText
            Task {
                if await model.addComment(text) { commentText = "" }
            }
        }

        private func move(to column: String) {
            Task { _ = await model.move(to: column) }
        }

        private func reassign(to profile: String) {
            Task { _ = await model.reassign(to: profile) }
        }

        private func specify() {
            Task { _ = await model.specify() }
        }

        private func perform(_ action: KanbanTaskAction) {
            switch action {
            case .reclaim:
                Task { _ = await model.reclaim() }
            case .delete:
                Task {
                    if await model.delete() { dismiss() }
                }
            }
        }

        private static func eventTime(_ unixSeconds: Int) -> String {
            Date(timeIntervalSince1970: TimeInterval(unixSeconds)).formatted(date: .abbreviated, time: .shortened)
        }
    }

    #Preview("Task, outer", traits: .fixedLayout(width: 466, height: 678)) {
        if let detail = KanbanSampleData.detail {
            KanbanTaskSheet(
                card: KanbanCard(id: detail.task.id, title: detail.task.title), model: .preview(detail: detail),
                columns: KanbanSampleData.columnNames, assignees: KanbanSampleData.assignees)
        }
    }

    #Preview("Task, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        if let detail = KanbanSampleData.detail {
            KanbanTaskSheet(
                card: KanbanCard(id: detail.task.id, title: detail.task.title), model: .preview(detail: detail),
                columns: KanbanSampleData.columnNames, assignees: KanbanSampleData.assignees)
        }
    }

    #Preview("Task, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        if let detail = KanbanSampleData.detail {
            KanbanTaskSheet(
                card: KanbanCard(id: detail.task.id, title: detail.task.title), model: .preview(detail: detail),
                columns: KanbanSampleData.columnNames, assignees: KanbanSampleData.assignees)
        }
    }

    #Preview("Task, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        if let detail = KanbanSampleData.detail {
            KanbanTaskSheet(
                card: KanbanCard(id: detail.task.id, title: detail.task.title), model: .preview(detail: detail),
                columns: KanbanSampleData.columnNames, assignees: KanbanSampleData.assignees)
        }
    }
#endif
