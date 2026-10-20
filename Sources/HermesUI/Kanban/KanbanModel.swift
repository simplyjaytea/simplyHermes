#if canImport(UIKit)
    import Foundation
    import HermesKit
    import Observation

    /// The boards of the active server and the one on screen (WP-55). Presence decides whether Tools shows Kanban.
    /// Each change goes to the server first, and the board then reloads from the server's answer.
    @MainActor
    @Observable
    final class KanbanModel {
        /// Nil until the check finishes. Anything but `.present` keeps the Tools row hidden.
        private(set) var presence: KanbanPresence?
        private(set) var boards: [KanbanBoardInfo] = []
        /// The board the server uses for every client unless the app picked another one.
        private(set) var serverCurrent: String?
        /// The slug on screen. Nil until the first load.
        private(set) var selectedSlug: String?
        /// The board on screen, with its columns in the order the server sends them.
        private(set) var board: KanbanBoardView?
        /// The column the page view shows. It stays across reloads while the column still exists.
        var selectedColumn = ""
        private(set) var isRefreshing = false
        /// Why the last load or change failed. The board on screen stays.
        private(set) var errorText: String?
        /// A note after a change, such as the server's warning for a new task.
        private(set) var notice: String?

        @ObservationIgnored let connections: ConnectionsModel
        private static let noBoardText = "Pick a board first."

        init(connections: ConnectionsModel) {
            self.connections = connections
        }

        var isAvailable: Bool { presence == .present }
        var selectedBoard: KanbanBoardInfo? { boards.first { $0.slug == selectedSlug } }
        var columnNames: [String] { board?.columns.map(\.name) ?? [] }
        var assignees: [String] { board?.assignees ?? [] }

        // MARK: Loading

        /// Checks for the plugin. Any failure leaves the Tools row hidden.
        func checkPresence() async {
            do {
                let rest = try await KanbanRemote.rest(connections)
                presence = try await rest.kanbanPresence()
            } catch {
                presence = nil
            }
        }

        /// Loads the board list, then the board on screen. Starts from the server's current board.
        func refresh() async {
            isRefreshing = true
            defer { isRefreshing = false }
            do {
                let rest = try await KanbanRemote.rest(connections)
                let listing = try await rest.kanbanBoards()
                boards = listing.boards.filter { $0.archived != true }
                serverCurrent = listing.current
                if selectedSlug == nil || !boards.contains(where: { $0.slug == selectedSlug }) {
                    selectedSlug = boards.first(where: { $0.slug == listing.current })?.slug ?? boards.first?.slug
                }
                setBoard(try await rest.kanbanBoard(selectedSlug))
                errorText = nil
            } catch is CancellationError {
                // A cancelled refresh keeps what is on screen.
            } catch {
                errorText = KanbanRemote.message(for: error)
            }
        }

        /// Shows another board on this device. The server's current board does not change.
        func select(_ slug: String) async {
            guard slug != selectedSlug else { return }
            selectedSlug = slug
            board = nil
            await refresh()
        }

        // MARK: Changes. Each one returns the failure text, or nil when it went through.

        /// Makes the selected board the server's current one. Other clients and the CLI follow it.
        func makeSelectedCurrent() async -> String? {
            guard let slug = selectedSlug else { return Self.noBoardText }
            return await change { try await $0.switchKanbanBoard(slug: slug) }
        }

        /// Creates a board and selects it. A slug that exists already returns that board.
        func createBoard(_ draft: KanbanBoardDraft) async -> String? {
            let previous = selectedSlug
            selectedSlug = draft.slug
            let failure = await change { try await $0.createKanbanBoard(draft) }
            if failure != nil { selectedSlug = previous }
            return failure
        }

        /// Renames the selected board or changes its details. The slug stays.
        func updateSelectedBoard(_ update: KanbanBoardUpdate) async -> String? {
            guard let slug = selectedSlug else { return Self.noBoardText }
            return await change { try await $0.updateKanbanBoard(slug: slug, update) }
        }

        /// Archives the selected board, or deletes it for good when `hard` is true.
        func removeSelectedBoard(hard: Bool) async -> String? {
            guard let slug = selectedSlug else { return Self.noBoardText }
            return await change { try await $0.deleteKanbanBoard(slug: slug, hard: hard) }
        }

        /// Asks the dispatcher to start ready tasks now instead of at its next tick.
        func dispatch() async -> String? {
            let slug = selectedSlug
            let failure = await change { try await $0.dispatchKanban(board: slug) }
            if failure == nil { notice = "Dispatch requested." }
            return failure
        }

        /// Creates a task on the selected board. The server's warning, such as no running gateway, becomes the notice.
        func createTask(_ draft: KanbanTaskDraft) async -> String? {
            notice = nil
            let slug = selectedSlug
            do {
                let rest = try await KanbanRemote.rest(connections)
                let created = try await rest.createKanbanTask(draft, board: slug)
                notice = created.warning
            } catch {
                return KanbanRemote.message(for: error)
            }
            await refresh()
            return nil
        }

        /// Runs one change on the server, then reloads the board.
        private func change(_ action: (RESTClient) async throws -> Void) async -> String? {
            notice = nil
            do {
                let rest = try await KanbanRemote.rest(connections)
                try await action(rest)
            } catch {
                let text = KanbanRemote.message(for: error)
                errorText = text
                return text
            }
            await refresh()
            return nil
        }

        private func setBoard(_ view: KanbanBoardView) {
            board = view
            if !columnNames.contains(selectedColumn) {
                selectedColumn = columnNames.first ?? ""
            }
        }

        /// A model with a fixed board, for previews and snapshots. It never reaches a server.
        static func preview(
            board: KanbanBoardView?, boards: [KanbanBoardInfo] = [], notice: String? = nil
        ) -> KanbanModel {
            let model = KanbanModel(connections: .preview())
            model.presence = .present
            model.boards = boards
            model.serverCurrent = boards.first?.slug
            model.selectedSlug = boards.first?.slug
            model.board = board
            model.selectedColumn = board?.columns.first?.name ?? ""
            model.notice = notice
            return model
        }
    }
#endif
