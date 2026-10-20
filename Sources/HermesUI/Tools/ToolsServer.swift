#if canImport(UIKit)
    import HermesKit
    import Observation
    import SwiftUI

    /// The signed-in REST client of the active server. It connects on demand, the way the Chats list does.
    @MainActor
    enum ToolsServer {
        static func rest(_ connections: ConnectionsModel?) async throws -> RESTClient {
            guard let connections, let connection = connections.active, let manager = connections.manager else {
                throw ToolsServerError.noActiveServer
            }
            _ = try await manager.client(for: connection)
            guard let rest = await manager.rest(for: connection.id) else {
                throw ConnectionUnavailable(phase: await manager.phase(of: connection.id))
            }
            return rest
        }
    }

    /// No server is selected in the app.
    enum ToolsServerError: Error, Equatable {
        case noActiveServer
    }

    /// Short messages for failed calls. The server's own `detail` wins when it sent one.
    enum ToolsMessages {
        /// A background change that ended with a failing exit code.
        static let failedAction = "The change did not finish on the server. Check the server log."

        static func text(for error: any Error) -> String {
            switch error {
            case ToolsServerError.noActiveServer: "Connect to a server first."
            case RESTError.unauthorized: "Sign in again to use this server."
            case RESTError.http(_, let detail?): detail
            case RESTError.rateLimited: "The server is busy. Try again in a moment."
            case is ConnectionUnavailable, RESTError.transport: "Could not reach the server."
            case is ServerActionTimeout: "The change is still running on the server. Refresh later."
            default: "That did not work. Try again."
            }
        }
    }

    /// A background change on the server (a skill install, a plugin update), shown while it runs.
    struct ToolsActivity: Equatable {
        var title: String
        /// The newest line of the server's log.
        var latest: String?
    }

    /// One row for a running or finished background change.
    struct ToolsActivityRow: View {
        let activity: ToolsActivity

        var body: some View {
            HStack(spacing: 12) {
                ProgressView()
                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.title)
                        .font(HermesFont.body.weight(.semibold))
                    if let latest = activity.latest, !latest.isEmpty {
                        Text(latest)
                            .font(HermesFont.codeSmall)
                            .foregroundStyle(HermesColor.secondaryText)
                            .lineLimit(2)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("tools.activity")
        }
    }

    /// Runs a server action (a skill install, a provider install) and keeps its row on screen while the process runs.
    @MainActor
    @Observable
    final class ToolsActionRunner {
        /// The change that runs now, or nil.
        private(set) var activity: ToolsActivity?

        /// Polls `start` until its process ends and returns the last status. Throws ``ServerActionTimeout`` when the
        /// process outlasts the poller's limit.
        func run(_ start: ServerActionStart, title: String, rest: RESTClient) async throws -> ServerActionStatus {
            activity = ToolsActivity(title: title, latest: nil)
            defer { activity = nil }
            return try await ServerActionPoller().finish(start.name, rest: rest) { status in
                await self.show(status.lines?.last)
            }
        }

        private func show(_ latest: String?) {
            activity?.latest = latest
        }
    }

    /// A line of feedback under a screen's title: a failure in the danger color, or a note in the secondary color.
    struct ToolsNotice: Equatable {
        var text: String
        var isError: Bool

        static func error(_ text: String) -> ToolsNotice {
            ToolsNotice(text: text, isError: true)
        }

        static func info(_ text: String) -> ToolsNotice {
            ToolsNotice(text: text, isError: false)
        }
    }

    /// One feedback line inside a list.
    struct ToolsNoticeRow: View {
        let notice: ToolsNotice

        var body: some View {
            Text(notice.text)
                .font(HermesFont.footnote)
                .foregroundStyle(notice.isError ? HermesColor.destructive : HermesColor.secondaryText)
                .accessibilityIdentifier(notice.isError ? "tools.error" : "tools.notice")
        }
    }
#endif
