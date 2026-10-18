#if canImport(UIKit)
    import Foundation
    import HermesKit
    import SwiftUI

    /// Creates a task on the selected board: title, description, assignee and priority (WP-55).
    struct KanbanNewTaskForm: View {
        let model: KanbanModel

        @Environment(\.dismiss) private var dismiss
        @State private var title = ""
        @State private var details = ""
        @State private var assignee = ""
        @State private var priorityText = "0"
        @State private var problem: String?
        @State private var isCreating = false

        init(model: KanbanModel) {
            self.model = model
        }

        var body: some View {
            NavigationStack {
                Form {
                    Section {
                        TextField("Title", text: $title)
                            .accessibilityIdentifier("kanban.newTask.title")
                        TextField("Description", text: $details, axis: .vertical)
                    }
                    Section {
                        Picker("Assignee", selection: $assignee) {
                            Text("Unassigned").tag("")
                            ForEach(model.assignees, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                        TextField("Priority", text: $priorityText)
                            .keyboardType(.numbersAndPunctuation)
                    } footer: {
                        Text("A higher priority runs first. It is a whole number.")
                    }
                    if let problem {
                        Section {
                            Label(problem, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(HermesColor.destructive)
                        }
                    }
                }
                .navigationTitle("New task")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create", action: create)
                            .disabled(isCreating || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("kanban.newTask.create")
                    }
                }
            }
        }

        private func create() {
            guard let priority = Int(priorityText.trimmingCharacters(in: .whitespaces)) else {
                problem = "Priority must be a whole number."
                return
            }
            let draft = KanbanTaskDraft(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                body: details.isEmpty ? nil : details,
                assignee: assignee.isEmpty ? nil : assignee,
                priority: priority)
            isCreating = true
            Task {
                if let failure = await model.createTask(draft) {
                    problem = failure
                    isCreating = false
                } else {
                    dismiss()
                }
            }
        }
    }

    /// Creates a board, or renames the selected one (WP-55). The slug is fixed once the board exists.
    struct KanbanBoardForm: View {
        enum Mode: Identifiable {
            case create
            case rename(KanbanBoardInfo)

            var id: String {
                switch self {
                case .create: "create"
                case .rename(let board): "rename.\(board.slug)"
                }
            }
        }

        let mode: Mode
        let model: KanbanModel

        @Environment(\.dismiss) private var dismiss
        @State private var slug: String
        @State private var name: String
        @State private var details: String
        @State private var problem: String?

        init(mode: Mode, model: KanbanModel) {
            self.mode = mode
            self.model = model
            switch mode {
            case .create:
                _slug = State(initialValue: "")
                _name = State(initialValue: "")
                _details = State(initialValue: "")
            case .rename(let board):
                _slug = State(initialValue: board.slug)
                _name = State(initialValue: board.name)
                _details = State(initialValue: board.description ?? "")
            }
        }

        private var isCreating: Bool {
            if case .create = mode { return true }
            return false
        }

        var body: some View {
            NavigationStack {
                Form {
                    Section {
                        if isCreating {
                            TextField("Slug", text: $slug)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .accessibilityIdentifier("kanban.board.slug")
                        }
                        TextField("Name", text: $name)
                        TextField("Description", text: $details, axis: .vertical)
                    } footer: {
                        Text(
                            isCreating
                                ? "The slug names the board on the server. It can't be changed later."
                                : "The slug stays the same. An empty description clears it.")
                    }
                    if let problem {
                        Section {
                            Label(problem, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(HermesColor.destructive)
                        }
                    }
                }
                .navigationTitle(isCreating ? "New board" : "Rename board")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", action: save)
                            .disabled(isCreating && slug.trimmingCharacters(in: .whitespaces).isEmpty)
                            .accessibilityIdentifier("kanban.board.save")
                    }
                }
            }
        }

        private func save() {
            let trimmedName: String? = name.isEmpty ? nil : name
            let trimmedSlug = slug.trimmingCharacters(in: .whitespaces)
            let description: String? = details.isEmpty ? nil : details
            let current = mode
            Task {
                let failure: String?
                switch current {
                case .create:
                    let draft = KanbanBoardDraft(slug: trimmedSlug, name: trimmedName, description: description)
                    failure = await model.createBoard(draft)
                case .rename:
                    failure = await model.updateSelectedBoard(
                        KanbanBoardUpdate(name: trimmedName, description: details))
                }
                if let failure {
                    problem = failure
                } else {
                    dismiss()
                }
            }
        }
    }

    #Preview("New task, outer", traits: .fixedLayout(width: 466, height: 678)) {
        KanbanNewTaskForm(model: .preview(board: KanbanSampleData.board, boards: KanbanSampleData.boards))
    }

    #Preview("New task, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        KanbanNewTaskForm(model: .preview(board: KanbanSampleData.board, boards: KanbanSampleData.boards))
    }

    #Preview("New task, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        KanbanNewTaskForm(model: .preview(board: KanbanSampleData.board, boards: KanbanSampleData.boards))
    }

    #Preview("New task, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        KanbanNewTaskForm(model: .preview(board: KanbanSampleData.board, boards: KanbanSampleData.boards))
    }

    #Preview("Board form, outer", traits: .fixedLayout(width: 466, height: 678)) {
        if let board = KanbanSampleData.boards.first {
            KanbanBoardForm(
                mode: .rename(board), model: .preview(board: KanbanSampleData.board, boards: KanbanSampleData.boards))
        }
    }

    #Preview("Board form, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        KanbanBoardForm(mode: .create, model: .preview(board: nil, boards: KanbanSampleData.boards))
    }

    #Preview("Board form, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        KanbanBoardForm(mode: .create, model: .preview(board: nil, boards: KanbanSampleData.boards))
    }

    #Preview("Board form, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        KanbanBoardForm(mode: .create, model: .preview(board: nil, boards: KanbanSampleData.boards))
    }
#endif
