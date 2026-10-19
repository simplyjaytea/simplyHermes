#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// Add a Hermes Cloud agent (WP-17): sign in, pick an organization when there are several, pick an agent, connect.
    ///
    /// UNTESTED LIVE: the portal calls behind it are a guess (see ``NousPortalClient``).
    public struct CloudConnectView: View {
        @State private var model: CloudConnectModel
        private let onDone: (ServerConnection?) -> Void
        @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
        @Environment(\.hermesReduceMotion) private var reduceMotionOverride

        /// `onDone` gets the connected agent, or nil when the user cancelled.
        public init(connections: ConnectionsModel, onDone: @escaping (ServerConnection?) -> Void) {
            _model = State(initialValue: CloudConnectModel(connections: connections, onConnected: { onDone($0) }))
            self.onDone = onDone
        }

        /// A view over a model that stands at a given step. For previews.
        init(model: CloudConnectModel, onDone: @escaping (ServerConnection?) -> Void = { _ in }) {
            _model = State(initialValue: model)
            self.onDone = onDone
        }

        private var reduceMotion: Bool {
            HermesMotion.resolveReduceMotion(system: systemReduceMotion, override: reduceMotionOverride)
        }

        public var body: some View {
            NavigationStack {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(HermesColor.groupedBackground)
                    .navigationTitle("Hermes Cloud")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                model.cancel()
                                onDone(nil)
                            }
                            .accessibilityIdentifier("cloud.cancel")
                        }
                    }
            }
            .interactiveDismissDisabled(model.isBusy)
            .animation(HermesMotion.animation(HermesMotion.gentle, reduceMotion: reduceMotion), value: model.step)
        }

        @ViewBuilder
        private var content: some View {
            switch model.step {
            case .signIn:
                CloudSignInStep(model: model)
            case .working(let text):
                CloudWorkingStep(text: text)
            case .chooseOrganization:
                CloudOrganizationStep(model: model)
            case .chooseAgent:
                CloudAgentStep(model: model)
            case .problem(let problem):
                CloudProblemStep(problem: problem, model: model)
            }
        }
    }

    // MARK: - Steps

    /// The round-cornered icon at the top of a step, like the Welcome screen's.
    private struct CloudBadge: View {
        let systemImage: String
        @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 40
        @ScaledMetric(relativeTo: .largeTitle) private var iconBox: CGFloat = 88

        var body: some View {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(HermesColor.onAccent)
                .frame(width: iconBox, height: iconBox)
                .background(HermesColor.accent.gradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .accessibilityHidden(true)
        }
    }

    /// Not signed in yet: one button.
    private struct CloudSignInStep: View {
        let model: CloudConnectModel

        var body: some View {
            ScrollView {
                VStack(spacing: 24) {
                    CloudBadge(systemImage: "cloud.fill")
                        .padding(.top, 16)
                    VStack(spacing: 8) {
                        Text("Sign in to Hermes Cloud")
                            .font(HermesFont.glanceTitle)
                            .multilineTextAlignment(.center)
                        Text("Sign in with your Nous account, then pick an agent. There is no address to type.")
                            .font(HermesFont.body)
                            .foregroundStyle(HermesColor.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    Button {
                        model.signIn()
                    } label: {
                        Label("Sign in", systemImage: "person.crop.circle")
                    }
                    .buttonStyle(HermesButtonStyle(.primary))
                    .accessibilityIdentifier("cloud.signIn")
                    Text("The sign-in stays in the Keychain on this iPhone only.")
                        .font(HermesFont.footnote)
                        .foregroundStyle(HermesColor.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: 420)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// Something runs: a spinner and what it does.
    private struct CloudWorkingStep: View {
        let text: String

        var body: some View {
            VStack(spacing: 16) {
                ProgressView()
                Text(text)
                    .font(HermesFont.body)
                    .foregroundStyle(HermesColor.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("cloud.working")
        }
    }

    /// Several organizations: pick one.
    private struct CloudOrganizationStep: View {
        let model: CloudConnectModel

        var body: some View {
            List {
                Section {
                    ForEach(model.selection.organizations) { organization in
                        Button {
                            model.chooseOrganization(organization.id)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "building.2")
                                    .foregroundStyle(HermesColor.accent)
                                    .frame(width: 28)
                                    .accessibilityHidden(true)
                                Text(organization.name).font(HermesFont.body.weight(.semibold))
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(HermesFont.footnote)
                                    .foregroundStyle(HermesColor.secondaryText)
                                    .accessibilityHidden(true)
                            }
                        }
                        .tint(HermesColor.primaryText)
                        .accessibilityIdentifier("cloud.organization.\(organization.id)")
                    }
                } header: {
                    Text("Organization")
                } footer: {
                    Text("Your login belongs to more than one organization. Pick the one whose agents you want.")
                }
            }
        }
    }

    /// The agents of the organization: pick one, then Connect.
    private struct CloudAgentStep: View {
        let model: CloudConnectModel

        var body: some View {
            List {
                Section {
                    ForEach(model.selection.agents) { agent in
                        Button {
                            model.chooseAgent(agent.id)
                        } label: {
                            CloudAgentRow(
                                agent: agent, isChosen: agent.id == model.selection.agentID,
                                isSaved: model.isSaved(agent))
                        }
                        .tint(HermesColor.primaryText)
                        .accessibilityIdentifier("cloud.agent.\(agent.id)")
                    }
                } header: {
                    Text(model.selection.organization?.name ?? "Agents")
                } footer: {
                    Text("Pick the agent to connect to. Hermes Cloud keeps it up to date.")
                }
                if model.selection.canChangeOrganization {
                    Section {
                        Button("Change organization") { model.changeOrganization() }
                            .accessibilityIdentifier("cloud.changeOrganization")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { connectBar }
        }

        private var connectBar: some View {
            VStack(spacing: 8) {
                if let agent = model.selection.agent, model.isSaved(agent) {
                    Text("\(agent.name) is already in your servers. Connect signs it in again.")
                        .font(HermesFont.footnote)
                        .foregroundStyle(HermesColor.secondaryText)
                        .multilineTextAlignment(.center)
                }
                Button {
                    model.connect()
                } label: {
                    Label("Connect", systemImage: "bolt.horizontal")
                }
                .buttonStyle(HermesButtonStyle(.primary))
                .disabled(model.selection.agent == nil)
                .accessibilityIdentifier("cloud.connect")
            }
            .frame(maxWidth: 420)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
    }

    /// One agent in the list: a mark for the pick, its name, and what the portal says it does.
    private struct CloudAgentRow: View {
        let agent: CloudAgent
        let isChosen: Bool
        let isSaved: Bool

        var body: some View {
            HStack(spacing: 12) {
                Image(systemName: isChosen ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isChosen ? HermesColor.accent : HermesColor.secondaryText)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.name).font(HermesFont.body.weight(.semibold))
                    if let caption {
                        Text(caption)
                            .font(HermesFont.caption)
                            .foregroundStyle(HermesColor.secondaryText)
                    }
                }
                Spacer(minLength: 8)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isChosen ? .isSelected : [])
        }

        private var caption: String? {
            let parts = [agent.status.caption, isSaved ? "Already added" : nil].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
    }

    /// Something stopped the flow: what happened, and the button that moves on.
    private struct CloudProblemStep: View {
        let problem: CloudProblem
        let model: CloudConnectModel
        @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 40

        var body: some View {
            ScrollView {
                VStack(spacing: 16) {
                    Image(systemName: problem.systemImage)
                        .font(.system(size: iconSize, weight: .semibold))
                        .foregroundStyle(HermesColor.statusWarning)
                        .accessibilityHidden(true)
                    Text(problem.title)
                        .font(HermesFont.headline)
                        .multilineTextAlignment(.center)
                    Text(problem.message)
                        .font(HermesFont.body)
                        .foregroundStyle(HermesColor.secondaryText)
                        .multilineTextAlignment(.center)
                    VStack(spacing: 12) {
                        Button(problem.actionTitle) { model.perform(problem.action) }
                            .buttonStyle(HermesButtonStyle(.primary))
                            .accessibilityIdentifier("cloud.problem.action")
                        if problem.concernsAgent && model.canReturnToAgents {
                            Button("Choose another agent") { model.returnToAgents() }
                                .buttonStyle(HermesButtonStyle(.secondary))
                                .accessibilityIdentifier("cloud.problem.agents")
                        }
                    }
                    .padding(.top, 8)
                }
                .frame(maxWidth: 420)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .onAppear { AccessibilityNotification.Announcement(problem.title).post() }
            .accessibilityIdentifier("cloud.problem")
        }
    }

    // MARK: - Previews

    #Preview("Hermes Cloud sign-in, outer", traits: .fixedLayout(width: 466, height: 678)) {
        CloudConnectView(model: .preview(.signIn))
    }

    #Preview("Hermes Cloud agents, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        CloudConnectView(model: .preview(.chooseAgent, selection: CloudSamples.agentsToChoose))
    }

    #Preview("Hermes Cloud organizations, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        CloudConnectView(model: .preview(.chooseOrganization, selection: CloudSamples.severalOrganizations))
    }

    #Preview("Hermes Cloud problem, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        CloudConnectView(model: .preview(.problem(.agentUnreachable(agent: "research-bot", detail: "it answered 502"))))
    }
#endif
