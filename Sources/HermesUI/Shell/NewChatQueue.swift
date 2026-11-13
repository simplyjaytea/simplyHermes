#if canImport(UIKit)
    import Foundation
    import HermesKit
    import Observation

    /// Makes the server session for a New chat on one saved server (board row 104). The coordinator only calls it while
    /// that server's status is connected, so `client(for:)` does not wait here.
    struct ServerSessionCreator: NewChatCreator {
        let connections: ConnectionsModel
        let connectionID: UUID

        func createSession() async throws -> String {
            let (connection, manager) = await MainActor.run {
                (connections.connection(id: connectionID), connections.manager)
            }
            guard let connection, let manager else { throw NewChatCreateError.unreachable }
            do {
                return try await manager.client(for: connection).createEmptySession()
            } catch let error as RPCError {
                // The server answered and said no. Its words are the reason.
                throw NewChatCreateError.refused(error.message)
            } catch {
                // Anything else is a lost connection: the message keeps waiting.
                throw NewChatCreateError.unreachable
            }
        }
    }

    /// The New chats the screen shows: the first message of each is saved before anything is tried, waits for its own
    /// server, and goes out once (``NewChatCoordinator``). This class only maps the coordinator's answers onto rows of the
    /// chat list, and it carries the rows' waiting messages for the screen.
    @MainActor
    @Observable
    public final class NewChatQueue {
        /// The waiting messages of each placeholder row, oldest first.
        public private(set) var waiting: [String: [OutboundRecord]] = [:]
        /// Why a row's chat could not be made, in the words the user reads. Retry, Edit or Delete follow.
        public private(set) var failures: [String: String] = [:]

        @ObservationIgnored private let connections: ConnectionsModel
        @ObservationIgnored private var coordinator: NewChatCoordinator!
        /// The saved placeholder behind a row. A row made in memory gets its placeholder at its first message.
        @ObservationIgnored private var placeholders: [String: PlaceholderChat] = [:]
        /// Called when a row's chat exists on the server: (row id, session id, server name, connection id).
        @ObservationIgnored var onCreated: (@MainActor (String, String, String, String) -> Void)?

        init(connections: ConnectionsModel, placeholders: any PlaceholderStore, outbox: any OutboxStore) {
            self.connections = connections
            coordinator = NewChatCoordinator(
                placeholders: placeholders, outbox: outbox,
                creator: { id in
                    UUID(uuidString: id).map { ServerSessionCreator(connections: connections, connectionID: $0) }
                },
                status: { id in await MainActor.run { Self.pill(of: id, in: connections) } },
                onCreated: { [weak self] chat, session in
                    await MainActor.run { self?.created(chat, sessionID: session) }
                })
        }

        /// The chat status of a saved server now: the same rules as a chat's pill.
        private static func pill(of connectionID: String, in connections: ConnectionsModel) -> PillState {
            guard let id = UUID(uuidString: connectionID) else { return .noServer }
            return ChatStatusDeriver.derive(
                backend: .server(connectionID: id, profile: nil, sessionID: ""), phase: connections.phases[id],
                path: NetworkMonitor.shared.path, local: .off
            ).pill
        }

        /// The status a placeholder row shows: its own server's, not the active one's.
        public func status(forRow row: String) -> ChatStatus {
            guard let chat = placeholders[row] ?? restoredRows[row], let id = UUID(uuidString: chat.connectionID) else {
                return ChatStatusDeriver.noServer
            }
            return ChatStatusDeriver.derive(
                backend: .server(connectionID: id, profile: nil, sessionID: ""), phase: connections.phases[id],
                path: NetworkMonitor.shared.path, local: .off)
        }

        /// The server a row is bound to, for the banner. Nil while the row has no first message yet.
        public func serverName(forRow row: String) -> String? {
            (placeholders[row] ?? restoredRows[row])?.serverName
        }

        /// Rows brought back after a relaunch, by row id.
        @ObservationIgnored private var restoredRows: [String: PlaceholderChat] = [:]

        /// Saves `text` as the first message of a row, then delivers it when its server is connected. The text is in
        /// the outbox when this returns; it throws if it could not be saved, and then nothing was queued.
        func send(_ text: String, forRow row: String) async throws {
            let chat = try bind(row)
            try await coordinator.ensureSaved(chat)
            let state = try await coordinator.send(text, in: chat.id)
            if case .createFailed(let reason) = state { failures[row] = reason } else { failures[row] = nil }
            await refresh(row: row)
        }

        /// Binds a row to the active server on its first message.
        private func bind(_ row: String) throws -> PlaceholderChat {
            if let existing = placeholders[row] ?? restoredRows[row] { return existing }
            guard let active = connections.active else {
                throw ServerNotConnectedError(serverName: "", isConnecting: false)
            }
            let chat = PlaceholderChat(
                connectionID: active.id.uuidString, serverName: active.name, createdAt: Date())
            placeholders[row] = chat
            return chat
        }

        /// A server connected or recovered: its placeholders try to deliver.
        func serverMayBeBack(_ connectionID: String) async {
            await coordinator.serverMayBeBack(connectionID: connectionID)
            for row in Set(placeholders.keys).union(restoredRows.keys) { await refresh(row: row) }
        }

        /// The banner's Try again: connect the row's own server, then deliver.
        func tryAgain(row: String) {
            guard let chat = placeholders[row] ?? restoredRows[row], let id = UUID(uuidString: chat.connectionID) else {
                return
            }
            connections.connect(id)
            Task {
                if failures[row] != nil { await coordinator.retry(chat.id) }
                await serverMayBeBack(chat.connectionID)
            }
        }

        /// The user's Retry on a failed first message.
        func retry(row: String) {
            guard let chat = placeholders[row] ?? restoredRows[row] else { return }
            Task {
                await coordinator.retry(chat.id)
                failures[row] = nil
                await refresh(row: row)
            }
        }

        /// Brings the saved placeholders back after a relaunch. Each returns as a row, with its waiting messages.
        func restore() async -> [PlaceholderChat] {
            guard let chats = try? await coordinator.restore() else { return [] }
            for chat in chats { restoredRows[chat.id] = chat }
            for chat in chats { await refresh(row: chat.id) }
            return chats
        }

        private func refresh(row: String) async {
            guard let chat = placeholders[row] ?? restoredRows[row] else { return }
            waiting[row] = (try? await coordinator.waiting(in: chat.id)) ?? waiting[row] ?? []
        }

        /// The row's chat exists on the server. The placeholder's messages now sit under the session id.
        private func created(_ chat: PlaceholderChat, sessionID: String) {
            let row = placeholders.first { $0.value.id == chat.id }?.key ?? chat.id
            placeholders[row] = nil
            restoredRows[chat.id] = nil
            waiting[row] = nil
            failures[row] = nil
            onCreated?(row, sessionID, chat.serverName, chat.connectionID)
        }
    }
#endif
