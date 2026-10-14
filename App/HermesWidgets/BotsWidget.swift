import HermesKit
import HermesUI
import SwiftUI
import WidgetKit

struct BotsEntry: TimelineEntry {
    let date: Date
    let content: BotsWidgetContent
}

/// Reads the snapshot the app writes to the shared container. Widgets never open a connection.
struct BotsProvider: TimelineProvider {
    func placeholder(in context: Context) -> BotsEntry {
        BotsEntry(date: .now, content: .snapshot(.sample(now: .now)))
    }

    func getSnapshot(in context: Context, completion: @escaping (BotsEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BotsEntry>) -> Void) {
        // The app reloads the timeline when bots or approvals change. Between reloads, one entry
        // every 5 minutes keeps "Updated … ago" and its stale color current.
        let first = currentEntry()
        let entries = (0..<12).map { step in
            BotsEntry(date: first.date.addingTimeInterval(Double(step) * 5 * 60), content: first.content)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func currentEntry() -> BotsEntry {
        let resolution = SharedContainer.resolve(
            infoDictionary: Bundle.main.infoDictionary,
            containerURL: { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
        )
        guard let directory = resolution.directory else {
            return BotsEntry(date: .now, content: .unavailable)
        }
        guard let snapshot = WidgetSnapshotStore(directory: directory).load() else {
            return BotsEntry(date: .now, content: .empty)
        }
        return BotsEntry(date: .now, content: .snapshot(snapshot))
    }
}

struct BotsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "bots", provider: BotsProvider()) { entry in
            BotsWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Bots")
        .description("Who is working, and what waits for your approval.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct BotsWidgetEntryView: View {
    let entry: BotsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            BotsCircularWidgetView(content: entry.content)
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
                .widgetURL(openURL)
        case .accessoryRectangular:
            BotsRectangularWidgetView(content: entry.content)
                .containerBackground(for: .widget) { Color.clear }
                .widgetURL(openURL)
        case .systemMedium:
            home(.medium)
        default:
            home(.small)
        }
    }

    private func home(_ size: BotsWidgetSize) -> some View {
        BotsWidgetView(content: entry.content, size: size, now: entry.date) { approval in
            HStack(spacing: 6) {
                Button(intent: DenyTurnIntent(sessionID: approval.sessionID)) {
                    LiveTurnCompactButtonLabel(.deny)
                }
                Button(intent: ApproveTurnIntent(sessionID: approval.sessionID)) {
                    LiveTurnCompactButtonLabel(.approve)
                }
            }
            .buttonStyle(.plain)
        }
        .containerBackground(HermesColor.background, for: .widget)
        .widgetURL(openURL)
    }

    /// Opens the chat waiting for approval, else just the app.
    private var openURL: URL? {
        guard case .snapshot(let snapshot) = entry.content, let approval = snapshot.approvals.first else {
            return nil
        }
        return HermesURL.chat(approval.sessionID)
    }
}
