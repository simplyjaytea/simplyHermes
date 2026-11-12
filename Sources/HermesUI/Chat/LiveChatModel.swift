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
        public private(set) var phase: Phase = .loading
        /// Providers and models for the model picker. Loaded when the chat attaches and after a switch.
        public private(set) var modelOptions: ModelOptionsResult?
        /// The model and reasoning level this device picked last, and its starred models.
        public private(set) var preferences = ModelPreferencesStore.load()
        /// Approvals of this chat that wait for the user.
        public private(set) var approvals: [PendingApproval] = []
        /// Typed messages the server does not have yet, oldest first. The screen shows them as "Waiting to send".
        public internal(set) var outboxRows: [OutboundRecord] = []
        /// Why the last save or send of a message failed. The screen shows it as a status line. Nil when none did.
        public internal(set) var outboxError: String?

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

        /// The newest assistant reply once it has finished streaming, with its item id. Voice speaks it (WP-60).
        public var newestFinishedReply: (id: String, text: String)? {
            for item in state.items.reversed() {
                guard case .assistant(let entry) = item.content else { continue }
                return entry.isStreaming ? nil : (item.id, entry.text)
            }
            return nil
        }

        /// Voice input for this chat. Nil when no server is connected. Dictated text goes to `insertText`.
        public func makeVoice(insertText: @escaping (String) -> Void) -> VoiceInputModel? {
            guard let connection = connections.active, let manager = connections.manager else { return nil }
            let id = connection.id
            return VoiceInputModel(
                server: { await manager.rest(for: id) },
                insertText: insertText,
                sendMessage: { [weak self] text in
                    // Dictated text that could not be saved is handed back to the composer, so it is not lost (M6).
                    Task {
                        if await self?.send(text) != true { self?.prefill = text }
                    }
                }
            )
        }

        /// The status strip readings for this chat: context fill, cache, speed and the connection.
        public var strip: ChatStatusStrip {
            ChatStatusStrip(usage: state.usage, connection: StripConnection(pill: status.pill))
        }

        /// This chat's status (WP-8): the one source for the pill, the composer and the banner. The network path comes
        /// from the shared monitor, so a missing network shows at once.
        public var status: ChatStatus {
            guard let connection = connections.active else { return ChatStatusDeriver.noServer }
            return ChatStatusDeriver.derive(
                backend: .server(connectionID: connection.id, profile: nil, sessionID: storedSessionID),
                phase: phase(of: connection.id), path: NetworkMonitor.shared.path, local: .off)
        }

        /// The connection phase the status reads. A test passes `phaseSource` to drive it; the app never does.
        private func phase(of id: UUID) -> ConnectionPhase? {
            if let phaseSource { return phaseSource() }
            return connections.phases[id]
        }

        /// The server's name for the pill and the banner.
        public var serverName: String { connections.active?.name ?? "the server" }

        #if DEBUG
            /// What a UI test reads when an outage assertion fails (WP-8): the status and every input it was derived from.
            public var debugStatusSummary: String {
                let phase =
                    connections.active.map { String(describing: connections.phases[$0.id]) } ?? "no active connection"
                return "pill=\(status.pill) canSend=\(status.canSend) path=\(NetworkMonitor.shared.path) phase=\(phase)"
            }
        #endif

        /// Delegated helpers of this chat, running ones first.
        public func subagentRows(now: Date) -> [SubagentRow] {
            SubagentPanel.rows(state.subagents, firstSeen: firstSeen, now: now)
        }

        @ObservationIgnored let connections: ConnectionsModel
        @ObservationIgnored private let broker: ServerRequestBroker
        @ObservationIgnored let storedSessionID: String
        /// The server this chat was opened on. Try again reconnects it, even if another server is active by then.
        @ObservationIgnored let serverID: UUID?
        /// When an automatic retry will fire, if one is scheduled.
        public private(set) var retryAt: Date?
        /// Text a slash command asked the composer to take back, unsent. The chat screen moves it into the draft.
        public internal(set) var prefill: String?
        @ObservationIgnored private var retryTask: Task<Void, Never>?
        @ObservationIgnored var controller: ChatSessionController?
        /// The attempt to connect and resume that is under way, if any. Calls to ``attach()`` share it.
        @ObservationIgnored private var attaching: Task<Void, Never>?
        @ObservationIgnored private var client: GatewayClient?
        @ObservationIgnored private var firstSeen: [String: Date] = [:]
        @ObservationIgnored private var wasRunning = false
        @ObservationIgnored private var tasks: [Task<Void, Never>] = []
        /// A New chat's first message, held until the chat attaches. ``attach()`` sends it.
        @ObservationIgnored private var firstMessage: (text: String, attachments: [ComposerAttachment])?
        @ObservationIgnored private var isMovingWorkspace = false
        @ObservationIgnored let outbox: any OutboxStore
        /// Where this chat's drainer lives. The app passes one registry for the whole process; each test model gets
        /// its own, so tests that reuse a chat id never share a drainer.
        @ObservationIgnored let drainers: OutboxDrainers
        /// Replaces the connection phases the status reads. Nil in the app; a test sets it to drive the pill.
        @ObservationIgnored let phaseSource: (@MainActor () -> ConnectionPhase?)?
        /// The pill as the chat last saw it, so a move back into `.connected` can send the waiting messages (WP-8).
        @ObservationIgnored var lastPill: PillState?
        /// Sends the outbox's messages through the attached controller. Created at the first attach and kept for the
        /// chat's life: a reattach points it at the new controller. A second drainer would not know about a message in
        /// flight and would send it again.
        @ObservationIgnored var drainer: OutboxDrainer?
        /// The server this chat's waiting messages belong to. Fixed for the model's life: a server switch builds a new
        /// model. The outbox keys messages by server and chat, since two servers can share a chat id.
        var outboxConnectionID: String { serverID?.uuidString ?? "" }
        /// True while ``retryConnection()`` runs, so a second tap does nothing.
        @ObservationIgnored private var retrying = false
        /// Set while the composer's send is saving. A second send starts only after it ends (review M5).
        @ObservationIgnored var composerSend = SingleFlight()
        /// The latest drain of this chat's waiting messages. Detaching cancels it, so a closed chat sends nothing more.
        @ObservationIgnored var drainTask: Task<Void, Never>?
        /// The profile this chat was pinned to at its first attach: the default by name when none was active.
        @ObservationIgnored private var pinnedProfile: String?
        @ObservationIgnored private var profilePinned = false

        init(
            connections: ConnectionsModel, broker: ServerRequestBroker, storedSessionID: String,
            outbox: any OutboxStore, drainers: OutboxDrainers = OutboxDrainers(),
            phaseSource: (@MainActor () -> ConnectionPhase?)? = nil
        ) {
            self.connections = connections
            self.broker = broker
            self.storedSessionID = storedSessionID
            self.serverID = connections.active?.id
            self.outbox = outbox
            self.drainers = drainers
            self.phaseSource = phaseSource
            state = TranscriptState(storedSessionID: storedSessionID)
            lastPill = status.pill
            watchPill()
        }

        /// Banner's Try again (WP-8). A chat that stayed attached keeps its old controller, so ``attach()`` alone does
        /// nothing after an outage. This reconnects the chat's own server and sends the waiting messages. While the
        /// server is still down the transcript stays on screen and the banner stays.
        public func retryConnection() async {
            // A second tap while a retry runs does nothing: two retries would race each other over the controller.
            guard !retrying else { return }
            retrying = true
            defer { retrying = false }
            guard let serverID, let connection = connections.connection(id: serverID), let manager = connections.manager
            else { return }
            connections.connect(serverID)
            guard let fresh = try? await manager.client(for: connection) else { return }
            // Attach only works on the active server, so a chat whose server is no longer active waits for a switch.
            guard connections.active?.id == serverID else { return }
            // The same client often recovers by itself and re-activates the chat's session. Its controller still works,
            // and tearing it down could send a message in flight a second time. Only drain.
            if controller != nil, fresh === client {
                await drainOutbox()
                return
            }
            detach()
            await attach()
        }

        /// Connects, resumes the session and starts following it. Safe to call again after a failure. A call made
        /// while another is still connecting waits for that one, so the session is never opened twice at once.
        public func attach() async {
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
                // The chat keeps the profile it first attached under. A later profile change, such as opening another
                // bot, does not move it (WP-5).
                if !profilePinned {
                    // A nil active profile pins to the default by name, so a later change cannot move this chat (M4).
                    pinnedProfile = ProfilePin.resolve(activeProfile: await client.activeProfile())
                    profilePinned = true
                }
                let controller = ChatSessionController(
                    transport: client, storedSessionID: storedSessionID, profile: pinnedProfile)
                let states = await controller.states()
                let pending = await broker.updates()
                try await controller.attach()
                self.controller = controller
                phase = .ready
                let refresh: @Sendable () async -> Void = { @MainActor [weak self] in await self?.refreshOutbox() }
                let (drainer, isNew) = drainers.drainer(forChat: storedSessionID, connection: outboxConnectionID) {
                    OutboxDrainer(
                        store: outbox, chatID: storedSessionID, connectionID: outboxConnectionID, submitter: controller,
                        onChange: refresh)
                }
                self.drainer = drainer
                do {
                    if isNew {
                        // The chat's first attach this launch: messages that were mid-send when the app stopped go out
                        // again, once.
                        try await drainer.recoverInterrupted()
                    } else {
                        // A reattach (Try again, a screen coming back, or this chat rebuilt after a server switch or in
                        // another window). A message may be in flight on the old controller, so nothing is recovered:
                        // the drainer finishes it there and sends the rest through this one.
                        await drainer.use(controller, onChange: refresh)
                    }
                    _ = try await outbox.pruneSent(inChat: storedSessionID)
                } catch {
                    outboxError = Self.outboxMessage(for: error)
                }
                tasks = [
                    Task { [weak self] in
                        for await next in states {
                            let firstInfo = self?.state.info == nil && next.transcript.info != nil
                            self?.noteTurnEnd(next.transcript.turn != nil)
                            self?.noteSubagents(next.transcript.subagents)
                            self?.noteWorkspace(next.transcript.info?.cwd)
                            self?.state = next.transcript
                            // Hermes is free again: the next waiting message may go.
                            if next.transcript.turn == nil { self?.drainSoon() }
                            if firstInfo, let info = next.transcript.info { self?.restoreModelPreferences(for: info) }
                        }
                    },
                    Task { [weak self] in
                        for await list in pending { self?.setApprovals(list) }
                    },
                ]
                await refreshOutbox()
                // A New chat's first message waits here until it is saved. If the save fails it stays for the next try.
                if let first = firstMessage, await send(first.text, attachments: first.attachments) {
                    firstMessage = nil
                }
                await drainOutbox()
            } catch {
                phase = .failed(Self.describe(error))
            }
        }

        /// Stops following. The last transcript stays on screen.
        public func detach() {
            for task in tasks { task.cancel() }
            retryTask?.cancel()
            tasks = []
            drainTask?.cancel()
            drainTask = nil
            let controller = controller
            self.controller = nil
            Task { await controller?.detach() }
        }

        /// Holds a New chat's first message until the chat attaches, and ``attach()`` sends it then. Text is saved to the
        /// outbox at hand-off, so it survives a relaunch before the chat attaches (M6). Files cannot be saved there yet,
        /// so they wait in memory, and so does text whose save failed.
        public func queueFirstMessage(_ text: String, attachments: [ComposerAttachment]) {
            guard attachments.isEmpty else {
                firstMessage = (text, attachments)
                return
            }
            Task {
                if await send(text) != true { firstMessage = (text, []) }
            }
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

        /// Loads the providers and models for the model picker.
        public func loadModelOptions() async {
            guard let client, let live = state.liveSessionID else { return }
            modelOptions = try? await client.modelOptions(ModelOptionsParams(sessionID: live))
        }

        /// The starred models that this server lists. A model starred on another server or profile stays out of the
        /// menu.
        public var listedFavorites: [ModelChoice] {
            modelOptions.map { preferences.listedFavorites(in: $0) } ?? []
        }

        /// The reasoning levels of the chat's model, as `model.options` reports them. Empty until the list has loaded,
        /// and for a model that does not reason.
        public var reasoningLevels: [String] {
            guard let options = modelOptions, let current = options.currentChoice else { return [] }
            return options.reasoningLevels(for: current)
        }

        /// Switches this chat to a model and remembers the pick on this device. A model the server holds comes back as
        /// `.needsConfirmation`. Call again with `confirmed` once the user agrees.
        public func chooseModel(_ choice: ModelChoice, confirmed: Bool = false) async throws -> ModelSwitchOutcome {
            guard let client, let live = state.liveSessionID else { throw GatewayClientError.notConnected }
            let value = choice.configValue(currentProvider: modelOptions?.provider)
            let params = ConfigSetParams(key: "model", value: value, sessionID: live, confirmExpensiveModel: confirmed)
            let outcome = try await client.configSet(params).outcome
            if case .applied = outcome {
                updatePreferences { $0.sticky = choice }
                await loadModelOptions()
            }
            return outcome
        }

        /// Sets the reasoning level of this session and remembers it on this device.
        public func chooseEffort(_ level: String) async throws {
            guard let client, let live = state.liveSessionID else { throw GatewayClientError.notConnected }
            let params = ConfigSetParams(key: "reasoning", value: level, sessionID: live, scope: "session")
            _ = try await client.configSet(params)
            updatePreferences { $0.stickyEffort = level }
        }

        /// Stars a model for the picker, or unstars it.
        public func toggleFavorite(_ choice: ModelChoice) {
            updatePreferences { $0.toggleFavorite(choice) }
        }

        /// Applies a change to the device's preferences. It starts from the saved copy, so a change made in another
        /// chat is kept.
        private func updatePreferences(_ change: (inout ModelPreferences) -> Void) {
            var updated = ModelPreferencesStore.load()
            change(&updated)
            ModelPreferencesStore.save(updated)
            preferences = updated
        }

        /// Brings a chat that just opened to the remembered model and reasoning level. The picker's list loads first.
        /// Only a model that this server lists is sent, and a list that does not load leaves the chat as it is. A
        /// switch the server holds for confirmation is not forced.
        private func restoreModelPreferences(for info: SessionInfo) {
            guard let client, let live = state.liveSessionID else { return }
            Task { [weak self] in
                await self?.loadModelOptions()
                guard let self, let options = self.modelOptions else { return }
                self.preferences = ModelPreferencesStore.load()
                let changes = self.preferences.restoreParams(for: info, sessionID: live, options: options)
                guard !changes.isEmpty else { return }
                for change in changes { _ = try? await client.configSet(change) }
                await self.loadModelOptions()
            }
        }

        /// Clears ``prefill`` once the composer has taken its text.
        public func clearPrefill() {
            prefill = nil
        }

        /// Sends the text into the running reply instead of queueing it. Falls back to a normal send, which saves the text
        /// to the outbox. Text that could not be sent or saved goes back to the composer.
        public func steer(_ text: String) {
            Task {
                if let controller, await controller.steer(text) { return }
                if await !send(text) { prefill = text }
            }
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
            let chat = LiveChatModel(
                connections: connections, broker: broker, storedSessionID: sessionID, outbox: OutboxServices.store,
                drainers: OutboxServices.drainers)
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
