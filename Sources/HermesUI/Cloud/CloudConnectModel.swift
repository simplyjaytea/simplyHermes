#if canImport(UIKit)
    import Foundation
    import HermesKit
    import Observation

    /// The add-a-Hermes-Cloud-agent flow (WP-17): sign in, pick an organization (only when there are several), pick an
    /// agent, connect.
    ///
    /// The steps that need no screen live in HermesKit and are tested there: ``CloudDiscovery`` walks the portal,
    /// ``CloudSelection`` holds the picks and ``CloudProblem`` words the failures. This model keeps the state, runs the
    /// browser sign-in, and on Connect tests the agent, saves it and connects it.
    ///
    /// UNTESTED LIVE: the portal calls behind it are a guess (see ``NousPortalClient``). A wrong guess ends in a
    /// problem screen, never in a made-up agent.
    @MainActor
    @Observable
    public final class CloudConnectModel {
        /// What the sheet shows.
        public enum Step: Equatable, Sendable {
            /// Not signed in yet.
            case signIn
            /// Something runs; the text says what.
            case working(String)
            /// Several organizations to pick from.
            case chooseOrganization
            /// The agents of the chosen organization.
            case chooseAgent
            /// Something stopped the flow.
            case problem(CloudProblem)
        }

        public private(set) var step: Step = .signIn
        public private(set) var selection = CloudSelection()
        @ObservationIgnored private let connections: ConnectionsModel
        @ObservationIgnored private let onConnected: (ServerConnection) -> Void
        @ObservationIgnored private var tokens: NativeTokens?
        /// Tokens from signing in to one agent itself, for an agent that did not take the Hermes Cloud tokens.
        @ObservationIgnored private var agentSignIn: (agentID: String, tokens: NativeTokens)?
        @ObservationIgnored private var lastAttempt = Attempt.discover
        @ObservationIgnored private var work: Task<Void, Never>?

        private enum Attempt {
            case discover
            case connect
        }

        /// `onConnected` runs after the agent was tested, saved and connected.
        public init(connections: ConnectionsModel, onConnected: @escaping (ServerConnection) -> Void) {
            self.connections = connections
            self.onConnected = onConnected
        }

        /// True while something runs and the sheet should not be swiped away.
        public var isBusy: Bool {
            if case .working = step { return true }
            return false
        }

        /// True when an agent list exists to go back to after a connect problem.
        public var canReturnToAgents: Bool { !selection.agents.isEmpty }

        /// True when the agent is saved already, so Connect refreshes it instead of adding a second entry.
        public func isSaved(_ agent: CloudAgent) -> Bool {
            guard let organization = selection.organization else { return false }
            return connections.saved.contains(agent: agent, in: organization)
        }

        // MARK: Actions

        /// Opens the browser sign-in, then lists organizations and agents.
        public func signIn() {
            run { await $0.performSignIn() }
        }

        /// Picks an organization and loads its agents.
        public func chooseOrganization(_ id: String) {
            guard selection.chooseOrganization(id: id) else { return }
            run { await $0.discover() }
        }

        /// Picks an agent. Connect is a separate tap.
        public func chooseAgent(_ id: String) {
            selection.chooseAgent(id: id)
        }

        /// Goes back to the organization list.
        public func changeOrganization() {
            selection.clearOrganization()
            show(nil)
        }

        /// Goes back to the agent list after a problem with one agent.
        public func returnToAgents() {
            show(nil)
        }

        /// Tests the chosen agent, saves it and connects it. Nothing is saved when the test fails.
        public func connect() {
            run { await $0.performConnect() }
        }

        /// Does what a problem screen's primary button says.
        public func perform(_ action: CloudProblem.Action) {
            switch action {
            case .signIn:
                signIn()
            case .signInToAgent:
                run { await $0.performAgentSignIn() }
            case .retry:
                run { await $0.retryLastAttempt() }
            case .checkAgain:
                selection.refresh()
                run { await $0.discover() }
            case .chooseOrganization:
                selection.clearOrganization()
                show(nil)
            }
        }

        /// Stops whatever runs. The sheet calls this when the user cancels.
        public func cancel() {
            work?.cancel()
            work = nil
        }

        /// Returns when the step that runs now has ended. For tests.
        public func waitUntilIdle() async {
            await work?.value
        }

        // MARK: Steps

        private func run(_ operation: @escaping @MainActor (CloudConnectModel) async -> Void) {
            work?.cancel()
            work = Task { await operation(self) }
        }

        private func retryLastAttempt() async {
            switch lastAttempt {
            case .discover: await discover()
            case .connect: await performConnect()
            }
        }

        private func performSignIn() async {
            step = .working("Signing in…")
            do {
                let result = try await connections.services.browserSignIn.signIn(
                    endpoint: connections.services.cloudPortal.endpoint, options: nil, provider: HermesCloud.provider)
                guard case .tokens(let signedIn) = result else {
                    step = .problem(.signInFailed("Hermes Cloud sent no token."))
                    return
                }
                tokens = signedIn
                agentSignIn = nil
                selection = CloudSelection()
                await discover()
            } catch {
                guard !Task.isCancelled else { return }
                if let problem = CloudProblem(signInError: error) {
                    step = .problem(problem)
                } else {
                    step = .signIn
                }
            }
        }

        /// Signs in to the chosen agent itself, for an agent that did not take the Hermes Cloud tokens, then connects.
        private func performAgentSignIn() async {
            guard case .ready(_, let agent) = selection.stage else { return }
            step = .working("Signing in to \(agent.name)…")
            do {
                let result = try await connections.services.browserSignIn.signIn(
                    endpoint: agent.endpoint, options: nil, provider: HermesCloud.provider)
                guard case .tokens(let signedIn) = result else {
                    step = .problem(.agentSignInRejected(agent: agent.name))
                    return
                }
                agentSignIn = (agent.id, signedIn)
            } catch {
                guard !Task.isCancelled else { return }
                step = .problem(CloudProblem(agentSignInError: error, agent: agent.name))
                return
            }
            await performConnect()
        }

        private func discover() async {
            guard let tokens else {
                step = .problem(.notSignedIn)
                return
            }
            lastAttempt = .discover
            step = .working(selection.organization.map { "Loading \($0.name)…" } ?? "Finding your agents…")
            let result = await CloudDiscovery(portal: connections.services.cloudPortal)
                .advance(selection, accessToken: tokens.accessToken)
            guard !Task.isCancelled else { return }
            selection = result.selection
            show(result.problem)
        }

        private func performConnect() async {
            guard case .ready(let organization, let agent) = selection.stage, let portalTokens = tokens else { return }
            lastAttempt = .connect
            step = .working("Connecting to \(agent.name)…")
            let connection = ServerConnection.cloud(organization: organization, agent: agent, saved: connections.saved)
            let ownTokens = agentSignIn.flatMap { $0.agentID == agent.id ? $0.tokens : nil }
            let secrets = ConnectionSecrets(nativeTokens: ownTokens ?? portalTokens)
            do {
                _ = try await connections.tester(for: connection).test(
                    connection, secrets: secrets,
                    progress: { testStep in
                        Task { @MainActor in self.progress(testStep) }
                    },
                    confirmHostKey: { _ in false })
            } catch let failure as ConnectionTestFailure {
                guard !Task.isCancelled else { return }
                step = .problem(CloudProblem(testFailure: failure, agent: agent.name))
                return
            } catch {
                guard !Task.isCancelled else { return }
                step = .problem(.agentUnreachable(agent: agent.name, detail: error.localizedDescription))
                return
            }
            guard !Task.isCancelled else { return }
            do throws(ConnectionSaveError) {
                try connections.save(connection, secrets: secrets)
            } catch {
                step = .problem(.connectionFailed(error.message))
                return
            }
            connections.connect(connection.id)
            onConnected(connection)
        }

        private func progress(_ testStep: ConnectionTestStep) {
            if case .working = step { step = .working(testStep.title) }
        }

        /// Shows the screen for where the selection stands, or the problem.
        private func show(_ problem: CloudProblem?) {
            if let problem {
                step = .problem(problem)
                return
            }
            switch selection.stage {
            case .chooseOrganization:
                step = .chooseOrganization
            case .chooseAgent, .ready:
                step = .chooseAgent
            case .noOrganizations:
                step = .problem(.noOrganizations)
            case .noAgents(let organization):
                step = .problem(.noAgents(organization: organization.name))
            case .needsOrganizations, .needsAgents:
                // Discovery resolves both before it returns without a problem; start over if one is left.
                run { await $0.discover() }
            }
        }
    }

    extension CloudConnectModel {
        /// A model standing at `step` with `selection`, for previews. Nothing runs.
        static func preview(
            _ step: Step, selection: CloudSelection = CloudSelection(), connections: ConnectionsModel = .preview([])
        ) -> CloudConnectModel {
            let model = CloudConnectModel(connections: connections, onConnected: { _ in })
            model.step = step
            model.selection = selection
            return model
        }
    }
#endif
