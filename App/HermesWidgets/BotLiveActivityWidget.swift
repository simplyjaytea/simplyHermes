import ActivityKit
import HermesKit
import HermesUI
import SwiftUI
import WidgetKit

/// The Live Activity on the Lock Screen and in the Dynamic Island. Buttons run App Intents in the app.
struct BotLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BotActivityAttributes.self) { context in
            LiveTurnCard(state: context.state, isStale: context.isStale) {
                LiveTurnButtonRow(state: context.state) { action in
                    intentButton(action, sessionID: context.attributes.sessionID) {
                        Text(action.title)
                    }
                }
            }
            .activitySystemActionForegroundColor(HermesColor.accent)
            .widgetURL(HermesURL.chat(context.attributes.sessionID))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LiveTurnAvatar(name: context.state.botName, phase: context.state.phase, size: 36)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    LiveTurnElapsed(state: context.state)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(LiveTurnText.headline(for: context.state))
                        .font(HermesFont.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        LiveTurnDetail(state: context.state, isStale: context.isStale)
                        HStack(spacing: 6) {
                            ForEach(LiveTurnAction.available(for: context.state), id: \.self) { action in
                                intentButton(action, sessionID: context.attributes.sessionID) {
                                    LiveTurnCompactButtonLabel(action)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            } compactLeading: {
                LiveTurnIslandLeading(state: context.state)
            } compactTrailing: {
                LiveTurnIslandTrailing(state: context.state)
            } minimal: {
                LiveTurnIslandMinimal(state: context.state)
            }
            .widgetURL(HermesURL.chat(context.attributes.sessionID))
            .keylineTint(HermesColor.accent)
        }
    }
}

/// A button that runs the matching intent for `action`.
@ViewBuilder
private func intentButton<Content: View>(
    _ action: LiveTurnAction,
    sessionID: String,
    @ViewBuilder label: () -> Content
) -> some View {
    switch action {
    case .stop: Button(intent: StopTurnIntent(sessionID: sessionID), label: label)
    case .deny: Button(intent: DenyTurnIntent(sessionID: sessionID), label: label)
    case .approve: Button(intent: ApproveTurnIntent(sessionID: sessionID), label: label)
    }
}
