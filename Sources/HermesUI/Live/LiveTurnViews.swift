#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    extension EnvironmentValues {
        /// Freezes elapsed-time text at this date, for snapshot tests. `nil` shows a live timer.
        @Entry public var hermesFrozenNow: Date? = nil  // swiftlint:disable:this redundant_optional_initialization
    }

    extension LiveTurnState.Phase {
        /// Short status text, as in the tent glance view.
        public var label: LocalizedStringKey {
            switch self {
            case .thinking: "Thinking"
            case .runningTool: "Running a tool"
            case .waitingForApproval: "Waiting for you"
            case .done: "Done"
            case .failed: "Failed"
            case .stopped: "Stopped"
            }
        }

        public var systemImage: String {
            switch self {
            case .thinking: "ellipsis.bubble.fill"
            case .runningTool: "terminal.fill"
            case .waitingForApproval: "exclamationmark.circle.fill"
            case .done: "checkmark.circle.fill"
            case .failed: "xmark.octagon.fill"
            case .stopped: "stop.circle.fill"
            }
        }

        public var tint: Color {
            switch self {
            case .thinking, .runningTool: HermesColor.accent
            case .waitingForApproval: HermesColor.statusWarning
            case .done: HermesColor.statusConnected
            case .failed: HermesColor.destructive
            case .stopped: HermesColor.statusOffline
            }
        }
    }

    extension LiveTurnAction {
        public var title: LocalizedStringKey {
            switch self {
            case .stop: "Stop"
            case .deny: "Deny"
            case .approve: "Approve"
            }
        }

        /// The glance view's button colors: Stop red, Deny plain, Approve accent.
        public var buttonKind: HermesButtonStyle.Kind {
            switch self {
            case .stop: .destructive
            case .deny: .secondary
            case .approve: .primary
            }
        }
    }

    /// The bot's initials in an accent circle; an orange ring while it waits for approval.
    public struct LiveTurnAvatar: View {
        private let name: String
        private let phase: LiveTurnState.Phase
        private let size: CGFloat

        public init(name: String, phase: LiveTurnState.Phase, size: CGFloat = 40) {
            self.name = name
            self.phase = phase
            self.size = size
        }

        public var body: some View {
            Text(initials)
                .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                .foregroundStyle(HermesColor.onAccent)
                .frame(width: size, height: size)
                .background(phase.isFinished ? HermesColor.statusOffline : HermesColor.accent, in: Circle())
                .overlay {
                    if phase == .waitingForApproval {
                        Circle().strokeBorder(HermesColor.statusWarning, lineWidth: max(2, size / 14))
                    }
                }
                .accessibilityHidden(true)
        }

        private var initials: String {
            let words = name.split(separator: " ").prefix(2)
            let letters = words.compactMap(\.first).map(String.init).joined()
            return letters.isEmpty ? "H" : letters.uppercased()
        }
    }

    /// Time since the turn started. A live timer, frozen in snapshot tests, hidden once the turn ends.
    public struct LiveTurnElapsed: View {
        private let state: LiveTurnState
        @Environment(\.hermesFrozenNow) private var frozenNow

        public init(state: LiveTurnState) {
            self.state = state
        }

        public var body: some View {
            Group {
                if state.phase.isFinished {
                    Image(systemName: state.phase.systemImage)
                        .foregroundStyle(state.phase.tint)
                } else if let frozenNow {
                    let elapsed = Duration.seconds(frozenNow.timeIntervalSince(state.startedAt))
                    Text(elapsed, format: .time(pattern: .minuteSecond))
                } else {
                    Text(timerInterval: state.startedAt...Date.distantFuture, countsDown: false)
                }
            }
            .font(HermesFont.subheadline.monospacedDigit().weight(.semibold))
            .multilineTextAlignment(.trailing)
        }
    }

    /// Lock Screen Live Activity: the tent glance view in card form.
    public struct LiveTurnCard<Controls: View>: View {
        private let state: LiveTurnState
        private let isStale: Bool
        private let controls: Controls

        public init(state: LiveTurnState, isStale: Bool = false, @ViewBuilder controls: () -> Controls) {
            self.state = state
            self.isStale = isStale
            self.controls = controls()
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    LiveTurnAvatar(name: state.botName, phase: state.phase)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(LiveTurnText.headline(for: state))
                            .font(HermesFont.headline)
                            .lineLimit(1)
                        Text(state.title)
                            .font(HermesFont.footnote)
                            .foregroundStyle(HermesColor.secondaryText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    LiveTurnElapsed(state: state)
                        .frame(minWidth: 56, alignment: .trailing)
                }
                LiveTurnDetail(state: state, isStale: isStale)
                controls
            }
            .padding(16)
        }
    }

    /// Status line, then the pending command or the last line of output. Shared by the card and the island.
    public struct LiveTurnDetail: View {
        private let state: LiveTurnState
        private let isStale: Bool

        public init(state: LiveTurnState, isStale: Bool) {
            self.state = state
            self.isStale = isStale
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Label(state.phase.label, systemImage: state.phase.systemImage)
                    .font(HermesFont.subheadline.weight(.semibold))
                    .foregroundStyle(state.phase.tint)
                if let command = state.pendingCommand, state.needsApproval {
                    Text(command)
                        .font(HermesFont.code)
                        .lineLimit(2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            HermesColor.fill,
                            in: RoundedRectangle(cornerRadius: HermesMetrics.innerRadius, style: .continuous))
                } else if !state.lastLine.isEmpty {
                    Text(state.lastLine)
                        .font(HermesFont.code)
                        .foregroundStyle(HermesColor.secondaryText)
                        .lineLimit(2)
                }
                if isStale && !state.phase.isFinished {
                    Label("Open simplyHermes to refresh", systemImage: "arrow.clockwise")
                        .font(HermesFont.caption.weight(.medium))
                        .foregroundStyle(HermesColor.statusWarning)
                }
            }
        }
    }

    /// Stop, Deny and Approve in a row. `button` wraps each label in the real button; the widget
    /// extension uses App Intent buttons, previews and snapshot tests use plain ones.
    public struct LiveTurnButtonRow<ButtonView: View>: View {
        private let actions: [LiveTurnAction]
        private let button: (LiveTurnAction) -> ButtonView

        public init(state: LiveTurnState, @ViewBuilder button: @escaping (LiveTurnAction) -> ButtonView) {
            actions = LiveTurnAction.available(for: state)
            self.button = button
        }

        public var body: some View {
            if !actions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(actions, id: \.self) { action in
                        button(action)
                            .buttonStyle(HermesButtonStyle(action.buttonKind))
                    }
                }
            }
        }
    }

    /// Text shared by the Live Activity, island and widgets.
    public enum LiveTurnText {
        public static func headline(for state: LiveTurnState) -> String {
            state.activeBotCount > 1 ? String(localized: "\(state.activeBotCount) bots working") : state.botName
        }
    }

    // MARK: Dynamic Island

    /// Compact island, leading side: the bot's avatar.
    public struct LiveTurnIslandLeading: View {
        private let state: LiveTurnState

        public init(state: LiveTurnState) {
            self.state = state
        }

        public var body: some View {
            LiveTurnAvatar(name: state.botName, phase: state.phase, size: 24)
        }
    }

    /// Compact island, trailing side: elapsed time, or an orange "!" while an approval waits.
    public struct LiveTurnIslandTrailing: View {
        private let state: LiveTurnState

        public init(state: LiveTurnState) {
            self.state = state
        }

        public var body: some View {
            if state.needsApproval {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(HermesColor.statusWarning)
                    .accessibilityLabel("Waiting for approval")
            } else {
                LiveTurnElapsed(state: state)
                    .frame(maxWidth: 52)
            }
        }
    }

    /// Minimal island (another app's activity shares the island): the "!" or the avatar.
    public struct LiveTurnIslandMinimal: View {
        private let state: LiveTurnState

        public init(state: LiveTurnState) {
            self.state = state
        }

        public var body: some View {
            if state.needsApproval {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(HermesColor.statusWarning)
                    .accessibilityLabel("Waiting for approval")
            } else {
                LiveTurnAvatar(name: state.botName, phase: state.phase, size: 22)
            }
        }
    }

    /// The expanded island laid out in a black capsule, for the gallery and snapshot tests.
    /// On device the widget extension places the same pieces into `DynamicIslandExpandedRegion`s.
    public struct LiveTurnIslandPreview<Controls: View>: View {
        private let state: LiveTurnState
        private let controls: Controls

        public init(state: LiveTurnState, @ViewBuilder controls: () -> Controls) {
            self.state = state
            self.controls = controls()
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    LiveTurnAvatar(name: state.botName, phase: state.phase, size: 36)
                    Text(LiveTurnText.headline(for: state))
                        .font(HermesFont.headline)
                        .lineLimit(1)
                    Spacer()
                    LiveTurnElapsed(state: state)
                }
                LiveTurnDetail(state: state, isStale: false)
                controls
            }
            .padding(18)
            .foregroundStyle(.white)
            .background(.black, in: RoundedRectangle(cornerRadius: 44, style: .continuous))
            .environment(\.colorScheme, .dark)
        }
    }
#endif
