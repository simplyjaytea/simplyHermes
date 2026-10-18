#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// A task opened in the sheet, with its own model, so the sheet keeps its state while the board reloads.
    struct KanbanOpenedTask: Identifiable {
        let task: KanbanTask
        let model: KanbanTaskModel

        var id: String { task.id }
    }

    /// The board-wide actions that ask first.
    private enum KanbanBoardAction: Hashable {
        case dispatch
        case archive
        case delete

        var title: String {
            switch self {
            case .dispatch: "Dispatch ready tasks now?"
            case .archive: "Archive this board?"
            case .delete: "Delete this board?"
            }
        }

        var buttonTitle: String {
            switch self {
            case .dispatch: "Dispatch"
            case .archive: "Archive board"
            case .delete: "Delete board"
            }
        }

        var message: String {
            switch self {
            case .dispatch: "The dispatcher starts ready tasks now instead of at its next tick."
            case .archive: "The board is archived on the server, not deleted. It leaves the board list."
            case .delete: "The board and its tasks are deleted from the server. This can't be undone."
            }
        }

        var isDestructive: Bool { self != .dispatch }
    }

    /// Tools > Kanban (WP-55): a board switcher, then one column per page (Q40). Tap a card for its details.
    struct KanbanBoardScreen: View {
        @Bindable var model: KanbanModel

        @State private var openedTask: KanbanOpenedTask?
        @State private var showsNewTask = false
        @State private var boardForm: KanbanBoardForm.Mode?
        @State private var pendingAction: KanbanBoardAction?

        init(model: KanbanModel) {
            self.model = model
        }

        var body: some View {
            VStack(spacing: 0) {
                banners
                content
            }
            .navigationTitle(model.selectedBoard?.name ?? "Kanban")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { boardToolbar }
            .task { await model.refresh() }
            .refreshable { await model.refresh() }
            .sheet(item: $openedTask) { opened in
                KanbanTaskSheet(
                    seed: opened.task, model: opened.model, columns: model.columnNames, assignees: model.assignees
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showsNewTask) {
                KanbanNewTaskForm(model: model)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(item: $boardForm) { mode in
                KanbanBoardForm(mode: mode, model: model)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .confirmationDialog(
                pendingAction?.title ?? "", isPresented: pendingBinding, titleVisibility: .visible,
                presenting: pendingAction
            ) { action in
                Button(action.buttonTitle, role: action.isDestructive ? .destructive : nil) { perform(action) }
            } message: { action in
                Text(action.message)
            }
        }

        @ViewBuilder
        private var banners: some View {
            if let errorText = model.errorText, model.board != nil {
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .font(HermesFont.footnote)
                    .foregroundStyle(HermesColor.destructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .accessibilityIdentifier("kanban.error")
            }
            if let notice = model.notice {
                Label(notice, systemImage: "info.circle")
                    .font(HermesFont.footnote)
                    .foregroundStyle(HermesColor.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .accessibilityIdentifier("kanban.notice")
            }
        }

        @ViewBuilder
        private var content: some View {
            if let board = model.board, !board.columns.isEmpty {
                TabView(selection: $model.selectedColumn) {
                    ForEach(board.columns, id: \.name) { column in
                        KanbanColumnPage(column: column) { task in
                            open(task)
                        }
                        .tag(column.name)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
            } else if model.board != nil {
                ContentUnavailableView(
                    "No columns", systemImage: "rectangle.3.group",
                    description: Text("The server sent this board without columns."))
            } else if let errorText = model.errorText {
                ContentUnavailableView(
                    "Couldn't load the board", systemImage: "wifi.slash", description: Text(errorText))
            } else {
                ProgressView()
            }
        }

        @ToolbarContentBuilder
        private var boardToolbar: some ToolbarContent {
            ToolbarItem(placement: .topBarLeading) {
                boardSwitcher
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showsNewTask = true
                } label: {
                    Label("New task", systemImage: "plus")
                }
                .disabled(model.board == nil)
                .accessibilityIdentifier("kanban.newTask")
            }
            ToolbarItem(placement: .primaryAction) {
                boardActions
            }
        }

        /// Picks the board on this device. New boards are made here too.
        private var boardSwitcher: some View {
            Menu {
                ForEach(model.boards) { board in
                    Button {
                        Task { await model.select(board.slug) }
                    } label: {
                        if board.slug == model.selectedSlug {
                            Label(board.name, systemImage: "checkmark")
                        } else {
                            Text(board.name)
                        }
                    }
                }
                Divider()
                Button("New board…", systemImage: "plus.rectangle.on.rectangle") { boardForm = .create }
            } label: {
                HStack(spacing: 4) {
                    Text(model.selectedBoard?.name ?? "Boards")
                        .font(HermesFont.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down").font(HermesFont.caption)
                }
            }
            .accessibilityIdentifier("kanban.boards")
        }

        private var boardActions: some View {
            Menu {
                if let current = model.selectedBoard {
                    Button("Rename board…", systemImage: "pencil") { boardForm = .rename(current) }
                }
                if model.selectedSlug != nil, model.selectedSlug != model.serverCurrent {
                    Button("Make current on server", systemImage: "star") {
                        Task { _ = await model.makeSelectedCurrent() }
                    }
                }
                Button("Dispatch ready tasks…", systemImage: "paperplane") { pendingAction = .dispatch }
                    .disabled(model.board == nil)
                Divider()
                Button("Archive board…", systemImage: "archivebox") { pendingAction = .archive }
                    .disabled(model.selectedSlug == nil)
                Button("Delete board…", systemImage: "trash", role: .destructive) { pendingAction = .delete }
                    .disabled(model.selectedSlug == nil)
            } label: {
                Label("Board actions", systemImage: "ellipsis.circle")
            }
            .accessibilityIdentifier("kanban.actions")
        }

        private var pendingBinding: Binding<Bool> {
            Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } })
        }

        private func open(_ task: KanbanTask) {
            let screenModel = model
            let taskModel = KanbanTaskModel(
                connections: model.connections, taskID: task.id, board: model.selectedSlug,
                onChange: { Task { await screenModel.refresh() } })
            openedTask = KanbanOpenedTask(task: task, model: taskModel)
        }

        private func perform(_ action: KanbanBoardAction) {
            switch action {
            case .dispatch:
                Task { _ = await model.dispatch() }
            case .archive:
                Task { _ = await model.removeSelectedBoard(hard: false) }
            case .delete:
                Task { _ = await model.removeSelectedBoard(hard: true) }
            }
        }
    }

    #Preview("Kanban, outer", traits: .fixedLayout(width: 466, height: 678)) {
        NavigationStack {
            KanbanBoardScreen(model: .preview(board: KanbanSampleData.board, boards: KanbanSampleData.boards))
        }
    }

    #Preview("Kanban, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        NavigationStack {
            KanbanBoardScreen(model: .preview(board: KanbanSampleData.board, boards: KanbanSampleData.boards))
        }
    }

    #Preview("Kanban, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        NavigationStack {
            KanbanBoardScreen(model: .preview(board: KanbanSampleData.board, boards: KanbanSampleData.boards))
        }
    }

    #Preview("Kanban, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        NavigationStack {
            KanbanBoardScreen(model: .preview(board: KanbanSampleData.board, boards: KanbanSampleData.boards))
        }
    }
#endif
