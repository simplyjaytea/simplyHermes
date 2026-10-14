#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// What a widget has to show: the app's cached snapshot, or why there is none.
    public enum BotsWidgetContent: Hashable, Sendable {
        case snapshot(WidgetSnapshot)
        /// The App Group works but the app has not written anything yet.
        case empty
        /// No shared container (App Group missing on this sideloaded build).
        case unavailable
    }

    /// Home Screen widget sizes the Bots widget supports.
    public enum BotsWidgetSize: Sendable {
        case small
        case medium
    }

    /// "Updated 12 min ago", orange once the cache is stale. Computed for the timeline entry's date,
    /// so the widget timeline adds an entry every few minutes to keep it current.
    struct WidgetUpdatedLabel: View {
        let snapshot: WidgetSnapshot
        let now: Date

        var body: some View {
            Text("Updated \(age)")
                .font(HermesFont.caption2)
                .foregroundStyle(snapshot.isStale(at: now) ? HermesColor.statusWarning : HermesColor.secondaryText)
                .lineLimit(1)
        }

        private var age: String {
            if now.timeIntervalSince(snapshot.updatedAt) < 60 {
                return String(localized: "just now")
            }
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            return formatter.localizedString(for: snapshot.updatedAt, relativeTo: now)
        }
    }

    /// One bot: a green dot while it works, then name and status.
    struct WidgetBotRow: View {
        let bot: WidgetSnapshot.Bot

        var body: some View {
            HStack(spacing: 6) {
                Circle()
                    .fill(bot.isActive ? HermesColor.statusConnected : HermesColor.statusOffline.opacity(0.5))
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(bot.name)
                        .font(HermesFont.footnote.weight(.semibold))
                        .lineLimit(1)
                    Text(bot.statusLine)
                        .font(HermesFont.caption2)
                        .foregroundStyle(HermesColor.secondaryText)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// The Bots widget: who is working and what waits for approval.
    /// `approvalButtons` draws Deny and Approve for the medium size; the extension passes App Intent buttons.
    public struct BotsWidgetView<ApprovalButtons: View>: View {
        private let content: BotsWidgetContent
        private let size: BotsWidgetSize
        private let now: Date
        private let approvalButtons: (WidgetSnapshot.Approval) -> ApprovalButtons

        public init(
            content: BotsWidgetContent,
            size: BotsWidgetSize,
            now: Date,
            @ViewBuilder approvalButtons: @escaping (WidgetSnapshot.Approval) -> ApprovalButtons
        ) {
            self.content = content
            self.size = size
            self.now = now
            self.approvalButtons = approvalButtons
        }

        public var body: some View {
            switch content {
            case .snapshot(let snapshot):
                switch size {
                case .small: small(snapshot)
                case .medium: medium(snapshot)
                }
            case .empty:
                WidgetUnavailableView(message: "Open simplyHermes to load your bots.")
            case .unavailable:
                WidgetUnavailableView(message: "Open simplyHermes to see your bots.")
            }
        }

        private func header(_ snapshot: WidgetSnapshot) -> some View {
            HStack(alignment: .firstTextBaseline) {
                Text("\(snapshot.activeBotCount)")
                    .font(.title2.weight(.bold).monospacedDigit())
                Text(snapshot.activeBotCount == 1 ? "bot working" : "bots working")
                    .font(HermesFont.footnote.weight(.semibold))
                    .foregroundStyle(HermesColor.secondaryText)
                    .lineLimit(1)
            }
        }

        private func waitingBadge(_ count: Int) -> some View {
            Label(count == 1 ? "1 waiting" : "\(count) waiting", systemImage: "exclamationmark.circle.fill")
                .font(HermesFont.caption.weight(.semibold))
                .foregroundStyle(HermesColor.statusWarning)
                .lineLimit(1)
        }

        private func small(_ snapshot: WidgetSnapshot) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                header(snapshot)
                ForEach(snapshot.bots.prefix(snapshot.approvals.isEmpty ? 3 : 2)) { bot in
                    WidgetBotRow(bot: bot)
                }
                Spacer(minLength: 0)
                if !snapshot.approvals.isEmpty {
                    waitingBadge(snapshot.approvals.count)
                }
                WidgetUpdatedLabel(snapshot: snapshot, now: now)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }

        private func medium(_ snapshot: WidgetSnapshot) -> some View {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    header(snapshot)
                    ForEach(snapshot.bots.prefix(3)) { bot in
                        WidgetBotRow(bot: bot)
                    }
                    Spacer(minLength: 0)
                    WidgetUpdatedLabel(snapshot: snapshot, now: now)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                if let approval = snapshot.approvals.first {
                    VStack(alignment: .leading, spacing: 6) {
                        waitingBadge(snapshot.approvals.count)
                        Text(approval.botName)
                            .font(HermesFont.footnote.weight(.semibold))
                            .lineLimit(1)
                        Text(approval.command)
                            .font(HermesFont.codeSmall)
                            .lineLimit(2)
                            .padding(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                HermesColor.fill,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        Spacer(minLength: 0)
                        approvalButtons(approval)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                            .font(.title2)
                            .foregroundStyle(HermesColor.statusConnected)
                        Text("Nothing waiting")
                            .font(HermesFont.footnote)
                            .foregroundStyle(HermesColor.secondaryText)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    /// A short Stop, Deny or Approve button label, for the medium widget and the Dynamic Island.
    public struct LiveTurnCompactButtonLabel: View {
        private let action: LiveTurnAction

        public init(_ action: LiveTurnAction) {
            self.action = action
        }

        public var body: some View {
            Text(action.title)
                .font(HermesFont.footnote.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 32)
                .foregroundStyle(action == .deny ? HermesColor.primaryText : HermesColor.onAccent)
                .background(fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }

        private var fill: Color {
            switch action {
            case .stop: HermesColor.destructive
            case .deny: HermesColor.fill
            case .approve: HermesColor.accent
            }
        }
    }

    /// Shown when the widget has no data: no App Group, or the app never ran.
    public struct WidgetUnavailableView: View {
        private let message: LocalizedStringKey

        public init(message: LocalizedStringKey) {
            self.message = message
        }

        public var body: some View {
            VStack(spacing: 6) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.title2)
                    .foregroundStyle(HermesColor.accent)
                Text(message)
                    .font(HermesFont.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(HermesColor.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Lock Screen circle: approvals waiting (with "!"), else bots working.
    public struct BotsCircularWidgetView: View {
        private let content: BotsWidgetContent

        public init(content: BotsWidgetContent) {
            self.content = content
        }

        public var body: some View {
            VStack(spacing: 0) {
                Image(systemName: symbol)
                    .font(.body.weight(.semibold))
                Text(count)
                    .font(.title3.weight(.bold).monospacedDigit())
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
        }

        private var snapshot: WidgetSnapshot? {
            if case .snapshot(let snapshot) = content { return snapshot }
            return nil
        }

        private var symbol: String {
            guard let snapshot else { return "bubble.left.and.bubble.right" }
            return snapshot.approvals.isEmpty ? "person.2.fill" : "exclamationmark.bubble.fill"
        }

        private var count: String {
            guard let snapshot else { return "–" }
            return "\(snapshot.approvals.isEmpty ? snapshot.activeBotCount : snapshot.approvals.count)"
        }

        private var accessibilityText: Text {
            guard let snapshot else { return Text("Open simplyHermes") }
            if snapshot.approvals.isEmpty {
                return Text("\(snapshot.activeBotCount) bots working")
            }
            return Text("\(snapshot.approvals.count) approvals waiting")
        }
    }

    /// Lock Screen line: bots working, then the first approval or the first busy bot.
    public struct BotsRectangularWidgetView: View {
        private let content: BotsWidgetContent

        public init(content: BotsWidgetContent) {
            self.content = content
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: 1) {
                Label("simplyHermes", systemImage: "bubble.left.and.bubble.right.fill")
                    .font(HermesFont.footnote.weight(.semibold))
                    .lineLimit(1)
                switch content {
                case .snapshot(let snapshot):
                    Text(snapshot.activeBotCount == 1 ? "1 bot working" : "\(snapshot.activeBotCount) bots working")
                        .font(HermesFont.footnote)
                        .lineLimit(1)
                    if let approval = snapshot.approvals.first {
                        Text("\(approval.botName) needs approval")
                            .font(HermesFont.footnote.weight(.semibold))
                            .lineLimit(1)
                    } else if let bot = snapshot.bots.first(where: \.isActive) {
                        Text("\(bot.name): \(bot.statusLine)")
                            .font(HermesFont.footnote)
                            .foregroundStyle(HermesColor.secondaryText)
                            .lineLimit(1)
                    }
                case .empty, .unavailable:
                    Text("Open the app to load bots")
                        .font(HermesFont.footnote)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
#endif

#if canImport(UIKit)
    extension WidgetSnapshot {
        /// Widget gallery placeholder and snapshot-test data.
        public static func sample(now: Date) -> WidgetSnapshot {
            WidgetSnapshot(
                bots: [
                    .init(id: "deploy", name: "Deploy bot", isActive: true, statusLine: "Waiting for you"),
                    .init(id: "research", name: "Researcher", isActive: true, statusLine: "Thinking"),
                    .init(id: "writer", name: "Writer", isActive: false, statusLine: "Idle"),
                ],
                approvals: [
                    .init(sessionID: "backup", botName: "Deploy bot", command: "ssh-copy-id backup@nas.local")
                ],
                updatedAt: now.addingTimeInterval(-120)
            )
        }
    }
#endif
