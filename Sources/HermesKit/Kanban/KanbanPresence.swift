import Foundation

/// Whether the server runs the kanban dashboard plugin (WP-55). The app shows Tools > Kanban only when it is present.
public enum KanbanPresence: Sendable, Equatable {
    /// The plugin's config endpoint answers.
    case present
    /// The config endpoint answers `404`: the plugin is not installed or not enabled.
    case absent
}

extension RESTClient {
    /// Checks for the kanban plugin with `GET /api/plugins/kanban/config`. `404` means ``KanbanPresence/absent``.
    /// Any other failure throws, so a dropped connection is never taken for a missing plugin.
    public func kanbanPresence() async throws -> KanbanPresence {
        do {
            _ = try await kanbanConfig()
            return .present
        } catch RESTError.http(let status, _) where status == 404 {
            return .absent
        }
    }
}
