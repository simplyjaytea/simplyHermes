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
        /// The folder this chat moved to in this run. Nil until the user picks one, then `state.info.cwd` is stale.
        /// It clears when the server reports another folder, since the server knows best.
        public private(set) var workspaceCwd: String?
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

        /// A cut (edit or regenerate) that waits for the user's yes: a deep cut or one that erases the chat (WP-34).
        public private(set) var pendingCut: PendingCut?
        /// Why the last edit or regenerate did not go through. Nil when it did or none ran.
        public private(set) var cutError: String?
        /// What the user typed for an edit the server has not taken, by the row it was for. The Edit sheet offers it
        /// again, so a failed edit or a cancelled question does not lose the text.
        public private(set) var unsentEdits: [Int: String] = [:]

        public struct PendingCut: Equatable {
            public let rowID: Int
            public let text: String
            public let confirmation: TurnEditConfirmation
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

        /// The on-device side of this chat: where messages go while the server is out of reach (WP-65b).
        public let offline: OfflineChatModel

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
        /// Text a slash command asked the composer to take back, unsent. The chat screen moves it into the draft.
        public private(set) var prefill: String?
        @ObservationIgnored private var retryTask: Task<Void, Never>?
        @ObservationIgnored private var controller: ChatSessionController?
        /// The attempt to connect and resume that is under way, if any. Calls to ``attach()`` share it.
        @ObservationIgnored private var attaching: Task<Void, Never>?
        @ObservationIgnored private var client: GatewayClient?
        @ObservationIgnored private var firstSeen: [String: Date] = [:]
        @ObservationIgnored private var wasRunning = false
        @ObservationIgnored private var tasks: [Task<Void, Never>] = []
        /// A New chat's first message, held until the chat attaches. ``attach()`` sends it.
        @ObservationIgnored private var firstMessage: (text: String, attachments: [ComposerAttachment])?
        @ObservationIgnored private var isMovingWorkspace = false

        init(connections: ConnectionsModel, broker: ServerRequestBroker, storedSessionID: String) {
            self.connections = connections
            self.broker = broker
            self.storedSessionID = storedSessionID
            state = TranscriptState(storedSessionID: storedSessionID)
            offline = OfflineChatModel(
                services: OfflineChatServices.shared, connections: connections, storedSessionID: storedSessionID)
        }

        /// Connects, resumes the session and starts following it. Safe to call again after a failure. A call made
        /// while another is still connecting waits for that one, so the session is never opened twice at once.
        public func attach() async {
            offline.start()
            if let attempt = attaching {
                await attempt.value
                return
            }
            guard controller == nil else { return }
            let attempt = Task { [weak self] in
                await self?.connectAndFollow()
                self?.attaching = nil
            }
            attaching = attempt
            await attempt.value
        }

        private func connectAndFollow() async {
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
                            self?.noteWorkspace(next.transcript.info?.cwd)
                            self?.state = next.transcript
                            self?.queue = next.queue
                        }
                    },
                    Task { [weak self] in
                        for await list in pending { self?.setApprovals(list) }
                    },
                ]
                if let first = firstMessage {
                    firstMessage = nil
                    send(first.text, attachments: first.attachments)
                }
            } catch {
                phase = .failed(Self.describe(error))
            }
        }

        /// Stops following. The last transcript stays on screen.
        public func detach() {
            for task in tasks { task.cancel() }
            retryTask?.cancel()
            offline.stop()
            tasks = []
            let controller = controller
            self.controller = nil
            Task { await controller?.detach() }
        }

        /// Holds a New chat's first message until the chat attaches, and ``attach()`` sends it then.
        public func queueFirstMessage(_ text: String, attachments: [ComposerAttachment]) {
            firstMessage = (text, attachments)
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
            // Plan Q44: while the server is out of reach, text goes to the on-device model. Files need Hermes.
            if attachments.isEmpty, offline.send(text) { return }
            guard let controller else { return }
            HermesSounds.play(.send)
            Task {
                if let composerText = await controller.send(text, attachments: attachments) { prefill = composerText }
            }
        }

        /// Clears ``prefill`` once the composer has taken its text.
        public func clearPrefill() {
            prefill = nil
        }

        /// "Send to Hermes" (plan Q44): sends the prompt of `offer`, written offline, to this chat once the server is
        /// back, then closes the offline chat. Opens the chat first when it never opened. While one send is under way
        /// a second tap does nothing, so the prompt reaches Hermes once. When the chat cannot open, nothing is sent and
        /// the offer stays.
        public func sendToHermes(_ offer: SendToHermesOffer) async {
            guard offline.beginSending(offer) else { return }
            if controller == nil { await attach() }
            guard controller != nil else {
                offline.sendFailed()
                return
            }
            send(offer.prompt)
            offline.resolveOffer(offer, as: .sent)
        }

        /// Sends the text into the running reply instead of queueing it. Falls back to sending normally.
        public func steer(_ text: String) {
            guard let controller else { return }
            Task { if await !controller.steer(text) { await controller.send(text) } }
        }

        /// Replaces the user turn at `rowID` and everything after it with `text`, then sends it (WP-34).
        public func edit(rowID: Int, text: String) {
            unsentEdits[rowID] = text
            runCut(fromRowID: rowID, text: text, consent: [])
        }

        /// Runs the last user turn again (WP-34).
        public func regenerate() {
            guard let last = lastUserTurn else { return }
            runCut(fromRowID: last.rowID, text: last.text, consent: [])
        }

        /// Answers the pending cut with the user's yes and runs it (WP-34).
        public func confirmPendingCut() {
            guard let cut = pendingCut else { return }
            pendingCut = nil
            runCut(fromRowID: cut.rowID, text: cut.text, consent: cut.confirmation.consent)
        }

        public func dismissPendingCut() {
            pendingCut = nil
        }

        public func clearCutError() {
            cutError = nil
        }

        /// Forks this chat into a new stored chat that shares the history so far (Q28). Nil when the fork fails.
        public func branch() async -> SessionBranchResult? {
            guard let client, let live = state.liveSessionID else { return nil }
            do {
                return try await client.branchSession(SessionBranchParams(sessionID: live))
            } catch {
                cutError = Self.describe(error)
                return nil
            }
        }

        /// The last user turn the server stored. Regenerate runs it again.
        private var lastUserTurn: (rowID: Int, text: String)? {
            for item in state.items.reversed() {
                if case .user(let entry) = item.content, let rowID = entry.rowID, entry.displayKind == nil {
                    return (rowID, entry.text)
                }
            }
            return nil
        }

        /// Runs the cut through the controller, so the transcript is cut and the reply lands under the edited message.
        private func runCut(fromRowID rowID: Int, text: String, consent: TurnEditConsent) {
            guard let controller else { return }
            Task { [weak self] in
                let outcome = await controller.edit(text: text, fromRowID: rowID, consent: consent)
                if let outcome { self?.noteCut(outcome, rowID: rowID, text: text) }
            }
        }

        private func noteCut(_ outcome: TurnEditOutcome, rowID: Int, text: String) {
            switch outcome {
            case .done:
                cutError = nil
                unsentEdits[rowID] = nil
            case .needsConfirmation(let confirmation):
                pendingCut = PendingCut(rowID: rowID, text: text, confirmation: confirmation)
            case .stale:
                // The controller has read the history again by now.
                cutError = "That message is no longer in this chat. Check the chat and try again."
            case .busy:
                cutError = "Hermes is still replying. Try again when it finishes."
            case .failed(let error):
                cutError = Self.describe(error)
            }
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

        /// Moves this chat into another folder on the server. Returns nil when it moved, else why the server refused,
        /// and only one move runs at a time (WP-37).
        public func moveWorkspace(to cwd: String) async -> String? {
            guard let client else { return String(localized: "The server is not reachable.") }
            guard !isMovingWorkspace else { return String(localized: "The chat is already moving.") }
            isMovingWorkspace = true
            defer { isMovingWorkspace = false }
            let params = SessionWorkspaceMoveParams(sessionKey: storedSessionID, cwd: cwd)
            do {
                workspaceCwd = try await client.moveSessionWorkspace(params).cwd
                return nil
            } catch {
                return Self.describe(error)
            }
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

        /// The server's folder wins once it changes, for example when another device moves the chat.
        private func noteWorkspace(_ cwd: String?) {
            if cwd != state.info?.cwd { workspaceCwd = nil }
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

        /// The chat for a stored session id if the store already holds one. Unlike ``chat(for:)``, it never creates one.
        public func existingChat(for sessionID: String) -> LiveChatModel? {
            guard connections.active?.id == serverID else { return nil }
            return chats[sessionID]
        }
    }
#endif
