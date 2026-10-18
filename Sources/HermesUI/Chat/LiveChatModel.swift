#if canImport(UIKit)
    import Foundation
    import HermesKit
    import Observation

    /// One server chat on screen (WP-30): the transcript, the approvals waiting in it, and the send and stop actions.
    @MainActor
    @Observable
    public final class LiveChatModel {
        public enum Phase: Equatable {
            case loading
            case ready
            case failed(String)
        }

        public private(set) var state: TranscriptState
        /// Messages waiting for Hermes to be free.
        public private(set) var queue = MessageQueue()
        public private(set) var phase: Phase = .loading
        /// Approvals of this chat that wait for the user.
        public private(set) var approvals: [PendingApproval] = []

        /// An approval request with the fields the inline card needs.
        public struct PendingApproval: Identifiable, Equatable {
            public let id: String
            public let command: String
            public let reason: String?
        }

        /// Clarify questions of this chat that wait for an answer.
        public private(set) var clarifies: [PendingClarify] = []
        /// A sudo password or secret value the server asks for. The sheet opens for the first one.
        public private(set) var valueRequests: [PendingValue] = []

        public struct PendingClarify: Identifiable, Equatable {
            public let id: String
            public let questions: [ClarifyQuestion]
        }

        public struct PendingValue: Identifiable, Equatable {
            public let id: String
            public let title: String
            public let detail: String?
        }

        public var isRunning: Bool { state.turn != nil }

        /// The status strip readings for this chat: context fill, cache, speed and the connection.
        public var strip: ChatStatusStrip {
            let phase = connections.active.flatMap { connections.phases[$0.id] }
            return ChatStatusStrip(usage: state.usage, connection: Self.connection(for: phase))
        }

        /// Delegated helpers of this chat, running ones first.
        public func subagentRows(now: Date) -> [SubagentRow] {
            SubagentPanel.rows(state.subagents, firstSeen: firstSeen, now: now)
        }

        @ObservationIgnored private let connections: ConnectionsModel
        @ObservationIgnored private let broker: ServerRequestBroker
        @ObservationIgnored private let storedSessionID: String
        /// When an automatic retry will fire, if one is scheduled.
        public private(set) var retryAt: Date?
        @ObservationIgnored private var retryTask: Task<Void, Never>?
        @ObservationIgnored private var controller: ChatSessionController?
        @ObservationIgnored private var client: GatewayClient?
        @ObservationIgnored private var firstSeen: [String: Date] = [:]
        @ObservationIgnored private var wasRunning = false
        @ObservationIgnored private var tasks: [Task<Void, Never>] = []

        init(connections: ConnectionsModel, broker: ServerRequestBroker, storedSessionID: String) {
            self.connections = connections
            self.broker = broker
            self.storedSessionID = storedSessionID
            state = TranscriptState(storedSessionID: storedSessionID)
        }

        /// Connects, resumes the session and starts following it. Safe to call again after a failure.
        public func attach() async {
            guard controller == nil else { return }
            guard let connection = connections.active, let manager = connections.manager else {
                phase = .failed("No server is selected.")
                return
            }
            phase = .loading
            do {
                let client = try await manager.client(for: connection)
                await broker.install(on: client)
                self.client = client
                let controller = ChatSessionController(transport: client, storedSessionID: storedSessionID)
                let states = await controller.states()
                let pending = await broker.updates()
                try await controller.attach()
                self.controller = controller
                phase = .ready
                tasks = [
                    Task { [weak self] in
                        for await next in states {
                            self?.noteTurnEnd(next.transcript.turn != nil)
                            self?.noteSubagents(next.transcript.subagents)
                            self?.state = next.transcript
                            self?.queue = next.queue
                        }
                    },
                    Task { [weak self] in
                        for await list in pending { self?.setApprovals(list) }
                    },
                ]
            } catch {
                phase = .failed(Self.describe(error))
            }
        }

        /// Stops following. The last transcript stays on screen.
        public func detach() {
            for task in tasks { task.cancel() }
            retryTask?.cancel()
            tasks = []
            let controller = controller
            self.controller = nil
            Task { await controller?.detach() }
        }

        /// Completions for a `/` command or an `@` mention, ranked by the server. Empty while the chat is not attached.
        public func complete(_ trigger: ComposerTrigger) async -> [CompletionItem] {
            guard let client else { return [] }
            let session = state.liveSessionID
            switch trigger {
            case .slash(let query):
                let result = try? await client.completeSlash(CompleteSlashParams(text: "/" + query, sessionID: session))
                return result?.items ?? []
            case .mention(let query):
                let result = try? await client.completePath(CompletePathParams(word: "@" + query, sessionID: session))
                return result?.items ?? []
            }
        }

        public func send(_ text: String, attachments: [ComposerAttachment] = []) {
            guard let controller else { return }
            HermesSounds.play(.send)
            Task { await controller.send(text, attachments: attachments) }
        }

        /// Sends the text into the running reply instead of queueing it. Falls back to sending normally.
        public func steer(_ text: String) {
            guard let controller else { return }
            Task { if await !controller.steer(text) { await controller.send(text) } }
        }

        public func editQueued(_ id: Int, to text: String) {
            guard let controller else { return }
            Task { await controller.editQueued(id, to: text) }
        }

        public func removeQueued(_ id: Int) {
            guard let controller else { return }
            Task { await controller.removeQueued(id) }
        }

        public func moveQueued(_ id: Int, to position: Int) {
            guard let controller else { return }
            Task { await controller.moveQueued(id, to: position) }
        }

        public func setQueuePaused(_ paused: Bool) {
            guard let controller else { return }
            Task { await controller.setQueuePaused(paused) }
        }

        /// Sends guidance to a running helper.
        public func steerSubagent(_ id: String, text: String) {
            guard let client, let live = state.liveSessionID else { return }
            let params = SubagentSteerParams(sessionID: live, subagentID: id, text: text)
            Task { _ = try? await client.steerSubagent(params) }
        }

        /// Stops a running helper.
        public func stopSubagent(_ id: String) {
            guard let client, let live = state.liveSessionID else { return }
            let params = SubagentInterruptParams(sessionID: live, subagentID: id)
            Task { _ = try? await client.interruptSubagent(params) }
        }

        private func noteSubagents(_ states: [SubagentState]) {
            for item in states where firstSeen[item.id] == nil { firstSeen[item.id] = Date() }
        }

        private static func connection(for phase: ConnectionPhase?) -> StripConnection {
            switch phase {
            case .connected?: .online
            case .reconnecting?, .connecting?, .openingTunnel?, .checkingServer?, .unlocking?: .reconnecting
            case .signInRequired?, .updateRequired?, .failed?: .needsAttention
            case .idle?, nil: .offline
            }
        }

        /// Sends the last prompt again.
        public func retry() {
            guard let controller else { return }
            Task { await controller.retryLast() }
        }

        /// Retries once at `date`, for a rate limit that lifts then. A second call replaces the first.
        public func scheduleRetry(at date: Date) {
            retryTask?.cancel()
            retryAt = date
            retryTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(max(0, date.timeIntervalSinceNow)))
                guard !Task.isCancelled else { return }
                self?.retryAt = nil
                self?.retry()
            }
        }

        public func cancelScheduledRetry() {
            retryTask?.cancel()
            retryTask = nil
            retryAt = nil
        }

        public func stop() {
            guard let controller else { return }
            Task { await controller.stop() }
        }

        /// Answers an approval card.
        public func answer(_ approval: PendingApproval, _ choice: ApprovalChoice) {
            let broker = broker
            Task { try? await broker.answer(approval.id, with: .approval(ApprovalAnswer(choice: choice))) }
        }

        /// Answers a clarify card. `answers` maps each question id to the chosen or typed text.
        public func answerClarify(_ item: PendingClarify, _ answers: [String: String]) {
            let broker = broker
            Task { try? await broker.answer(item.id, with: .clarify(ClarifyAnswer(answers: answers))) }
        }

        /// Answers a sudo or secret request. The value goes straight to the server and is never stored here.
        public func answerValue(_ item: PendingValue, _ value: String) {
            let broker = broker
            Task { try? await broker.answer(item.id, with: .value(ValueAnswer(value: value))) }
        }

        /// Closes a sudo or secret request without answering. The server stops waiting at its own timeout.
        public func dismissValue(_ item: PendingValue) {
            let broker = broker
            Task { await broker.cancel(item.id) }
        }

        /// Plays the done sound when a running turn stops.
        private func noteTurnEnd(_ isRunning: Bool) {
            if wasRunning, !isRunning { HermesSounds.play(.turnDone) }
            wasRunning = isRunning
        }

        private func setApprovals(_ list: [PendingServerRequest]) {
            let live = state.liveSessionID
            clarifies = list.compactMap { item in
                guard case .clarify(_, let request) = item.request, request.sessionID == live else { return nil }
                return PendingClarify(id: item.id, questions: request.questions)
            }
            valueRequests = list.compactMap { item in
                switch item.request {
                case .sudo(_, let request) where request.sessionID == live:
                    return PendingValue(id: item.id, title: "Password needed", detail: request.command)
                case .secret(_, let request) where request.sessionID == live:
                    return PendingValue(id: item.id, title: request.envVar, detail: request.prompt)
                default:
                    return nil
                }
            }
            let before = approvals.count
            approvals = list.compactMap { item in
                guard case .approval(_, let request) = item.request, request.sessionID == live else { return nil }
                return PendingApproval(
                    id: item.id, command: request.command ?? request.description ?? "A command",
                    reason: request.command == nil ? nil : request.description)
            }
            if approvals.count > before { HermesSounds.play(.approval) }
        }

        private static func describe(_ error: any Error) -> String {
            if let rpc = error as? RPCError { return rpc.message }
            if error is ConnectionUnavailable { return "The server is not reachable." }
            return "\(error)"
        }
    }

    /// Hands out one ``LiveChatModel`` per server chat, so folding and switching tabs keep the same transcript.
    @MainActor
    public final class LiveChatStore {
        private let connections: ConnectionsModel
        private let broker = ServerRequestBroker()
        private var chats: [String: LiveChatModel] = [:]
        private var serverID: UUID?

        public init(connections: ConnectionsModel) {
            self.connections = connections
        }

        /// The chat for a stored session id. Switching servers drops every chat of the old one.
        public func chat(for sessionID: String) -> LiveChatModel? {
            guard let active = connections.active, connections.manager != nil else { return nil }
            if serverID != active.id {
                for chat in chats.values { chat.detach() }
                chats = [:]
                serverID = active.id
            }
            if let existing = chats[sessionID] { return existing }
            let chat = LiveChatModel(connections: connections, broker: broker, storedSessionID: sessionID)
            chats[sessionID] = chat
            return chat
        }
    }
#endif
