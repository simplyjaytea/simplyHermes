#if canImport(UIKit)
    import Foundation
    import HermesKit
    import Observation

    /// One task in the detail sheet (WP-55): its comments and history, and the actions on it. Each change reloads the
    /// task and calls `onChange` so the board behind the sheet catches up.
    @MainActor
    @Observable
    final class KanbanTaskModel {
        private(set) var detail: KanbanTaskDetail?
        private(set) var isWorking = false
        /// Why the last action failed, such as the server's reason for refusing `done` without a result.
        private(set) var errorText: String?
        /// A note after an action that the server answers without data, such as a specify request.
        private(set) var notice: String?

        @ObservationIgnored private let connections: ConnectionsModel
        @ObservationIgnored let taskID: String
        @ObservationIgnored private let board: String?
        @ObservationIgnored private let onChange: @MainActor () -> Void

        init(
            connections: ConnectionsModel, taskID: String, board: String?, onChange: @escaping @MainActor () -> Void
        ) {
            self.connections = connections
            self.taskID = taskID
            self.board = board
            self.onChange = onChange
        }

        /// Reads the task with its comments and history.
        func load() async {
            do {
                let rest = try await KanbanRemote.rest(connections)
                detail = try await rest.kanbanTask(id: taskID, board: board)
                errorText = nil
            } catch is CancellationError {
                // A cancelled load keeps what is on screen.
            } catch {
                errorText = KanbanRemote.message(for: error)
            }
        }

        /// Adds a comment. The server records the author.
        func addComment(_ text: String) async -> Bool {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            let id = taskID
            let slug = board
            return await run { _ = try await $0.addKanbanComment(id: id, text: trimmed, board: slug) }
        }

        /// Moves the task to another column. A move is a status change, and the server can refuse it.
        func move(to status: String) async -> Bool {
            let change = KanbanBulkChange(ids: [taskID], status: status)
            let slug = board
            guard await run({ _ = try await $0.bulkUpdateKanbanTasks(change, board: slug) }) else { return false }
            // The bulk answer is per id and untyped, so the reloaded status is the check.
            if detail?.task.status != status {
                errorText = "The server did not move this task. Pull to refresh and try again."
                return false
            }
            return true
        }

        /// Gives the task to another profile.
        func reassign(to profile: String) async -> Bool {
            let id = taskID
            let slug = board
            return await run { _ = try await $0.reassignKanbanTask(id: id, to: profile, board: slug) }
        }

        /// Releases the running worker's claim. The worker is stopped.
        func reclaim() async -> Bool {
            let id = taskID
            let slug = board
            return await run { _ = try await $0.reclaimKanbanTask(id: id, board: slug) }
        }

        /// Asks the server to flesh out a triage task with the auxiliary model.
        func specify() async -> Bool {
            let id = taskID
            let slug = board
            let done = await run { _ = try await $0.specifyKanbanTask(id: id, board: slug) }
            if done { notice = "Specify requested. Pull to refresh to see the result." }
            return done
        }

        /// Deletes the task. Returns true when it is gone, so the sheet can close.
        func delete() async -> Bool {
            let id = taskID
            let slug = board
            isWorking = true
            defer { isWorking = false }
            do {
                let rest = try await KanbanRemote.rest(connections)
                try await rest.deleteKanbanTask(id: id, board: slug)
            } catch {
                errorText = KanbanRemote.message(for: error)
                return false
            }
            self.onChange()
            return true
        }

        /// Runs one action, then reloads the task and tells the board. Returns false when the action failed.
        private func run(_ action: (RESTClient) async throws -> Void) async -> Bool {
            isWorking = true
            defer { isWorking = false }
            notice = nil
            do {
                let rest = try await KanbanRemote.rest(connections)
                try await action(rest)
            } catch {
                errorText = KanbanRemote.message(for: error)
                return false
            }
            self.onChange()
            await load()
            return true
        }

        /// A model with a fixed task, for previews and snapshots. It never reaches a server.
        static func preview(detail: KanbanTaskDetail?, errorText: String? = nil) -> KanbanTaskModel {
            let model = KanbanTaskModel(connections: .preview(), taskID: "t_preview", board: nil, onChange: {})
            model.detail = detail
            model.errorText = errorText
            return model
        }
    }
#endif
