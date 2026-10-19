#if canImport(UIKit)
    import Foundation
    import HermesKit
    import Observation

    /// The sheet of one node on the memory screen (WP-52): it opens the full text, lets the user rewrite it and deletes
    /// the node after a confirmation.
    ///
    /// The model holds the whole flow, so the view only draws it. A save or a delete that the server accepts ends the
    /// flow: the model calls `onFinish` once, and the screen closes the sheet and loads the graph again. A refusal stays
    /// in ``problem`` and keeps the text the user typed. The words of the confirmation come from `JourneyNode`
    /// (`deleteMessage` and friends), where tests check them.
    @MainActor
    @Observable
    public final class NodeEditorModel: Identifiable {
        /// Where the flow stands.
        public enum Phase: Sendable, Equatable {
            /// Fetching the full text.
            case loading
            /// The text could not be fetched. The text is the reason.
            case failed(String)
            /// Reading.
            case viewing
            /// Typing.
            case editing
            /// Waiting for the server to take an edit.
            case saving
            /// Waiting for the server to delete the node.
            case deleting
        }

        /// How the flow ended.
        public enum Outcome: Sendable, Equatable {
            /// The server took the edit.
            case saved
            /// The server archived the skill or removed the memory chunk.
            case deleted
        }

        /// The node id, which is also the sheet's identity.
        public let id: String
        /// The node as the graph listed it.
        public let node: JourneyNode
        /// Where the flow stands.
        public private(set) var phase: Phase = .loading
        /// The text as the server has it.
        public private(set) var content = ""
        /// The text in the editor.
        public var draft = ""
        /// Why the last save or delete failed. Cleared by the next try.
        public private(set) var problem: String?
        /// True while the delete confirmation shows.
        public var confirmsDelete = false

        @ObservationIgnored private let backend: any JourneyBackend
        @ObservationIgnored private let onFinish: @MainActor (NodeEditorModel, Outcome) -> Void

        /// Creates the flow for `node`. `onFinish` runs when the server accepts a save or a delete.
        public init(
            node: JourneyNode, backend: any JourneyBackend,
            onFinish: @escaping @MainActor (NodeEditorModel, Outcome) -> Void
        ) {
            id = node.id
            self.node = node
            self.backend = backend
            self.onFinish = onFinish
        }

        // MARK: - Reading

        /// True while the server is working on a save or a delete, or the text is still on its way.
        public var isBusy: Bool {
            switch phase {
            case .loading, .saving, .deleting: true
            case .failed, .viewing, .editing: false
            }
        }

        /// True while the editor shows.
        public var isEditing: Bool { phase == .editing || phase == .saving }

        /// The typed text differs from the server's.
        public var hasChanges: Bool { isEditing && draft != content }

        /// The server takes the edit: there is a change, and the text is not empty.
        public var canSave: Bool {
            phase == .editing && draft != content && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        /// The text can be rewritten.
        public var canEdit: Bool { phase == .viewing }

        /// The node can be deleted. A pinned skill cannot: the server refuses it.
        public var canDelete: Bool {
            guard !node.pinned else { return false }
            switch phase {
            case .viewing, .failed: return true
            case .loading, .editing, .saving, .deleting: return false
            }
        }

        // MARK: - Actions

        /// Fetches the full text. Safe to call again after a failure. A cancelled call changes nothing, so the next
        /// call starts over.
        public func load() async {
            switch phase {
            case .loading, .failed: break
            case .viewing, .editing, .saving, .deleting: return
            }
            phase = .loading
            do {
                let detail = try await backend.learningNode(id: node.id)
                guard !Task.isCancelled else { return }
                content = detail.content
                draft = detail.content
                phase = .viewing
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(JourneyErrorText.message(for: error, doing: .open))
            }
        }

        /// Starts editing with the server's text.
        public func beginEditing() {
            guard canEdit else { return }
            draft = content
            problem = nil
            phase = .editing
        }

        /// Throws the typed text away and goes back to reading.
        public func cancelEditing() {
            guard phase == .editing else { return }
            draft = content
            problem = nil
            phase = .viewing
        }

        /// Sends the typed text. On success the flow ends with ``Outcome/saved``.
        public func save() async {
            guard canSave else { return }
            let text = draft
            phase = .saving
            problem = nil
            do {
                _ = try await backend.updateLearningNode(id: node.id, content: text)
                content = text
                phase = .viewing
                onFinish(self, .saved)
            } catch {
                problem = JourneyErrorText.message(for: error, doing: .save)
                phase = .editing
            }
        }

        /// Shows the delete confirmation.
        public func requestDelete() {
            guard canDelete else { return }
            confirmsDelete = true
        }

        /// Deletes the node after the user confirmed. On success the flow ends with ``Outcome/deleted``.
        public func delete() async {
            confirmsDelete = false
            guard canDelete else { return }
            let before = phase
            phase = .deleting
            problem = nil
            do {
                _ = try await backend.deleteLearningNode(id: node.id)
                onFinish(self, .deleted)
            } catch {
                problem = JourneyErrorText.message(for: error, doing: .delete)
                phase = before
            }
        }
    }
#endif
