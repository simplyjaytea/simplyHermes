import Foundation

/// Joins one path segment. `/` is encoded, so a name cannot add a path level.
func restPathSegment(_ value: String) -> String {
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "/")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
}

/// The answer of a server action that runs in the background: a hub skill install, uninstall or update, and a toolset
/// post-setup. The server starts a `hermes` process and answers at once. Poll it with ``RESTClient/actionStatus(_:lines:)``
/// or ``ServerActionPoller``.
public struct ServerActionStart: Sendable, Equatable, Codable {
    /// True when the process started.
    public var ok: Bool?
    /// Process id on the server.
    public var pid: Int?
    /// Action name for ``RESTClient/actionStatus(_:lines:)``.
    public var name: String
    /// The post-setup key, when the action runs a toolset post-setup.
    public var key: String?
}

/// `GET /api/actions/{name}/status`: the tail of an action's log and whether its process still runs.
public struct ServerActionStatus: Sendable, Equatable, Codable {
    /// Action name.
    public var name: String?
    /// True while the process runs.
    public var running: Bool?
    /// Exit code once the process has finished. Nil while it runs or when the server lost track of it.
    public var exitCode: Int?
    /// Process id on the server.
    public var pid: Int?
    /// The last lines of the action's log, oldest first.
    public var lines: [String]?

    /// True while the process runs.
    public var isRunning: Bool { running == true }

    /// True when the process finished with exit code 0.
    public var succeeded: Bool { !isRunning && exitCode == 0 }
}

/// A background action did not finish in the time the poller allows.
public struct ServerActionTimeout: Error, Sendable, Equatable {
    /// The action name.
    public var name: String

    /// Creates a value.
    public init(name: String) {
        self.name = name
    }
}

extension RESTClient {
    /// `GET /api/actions/{name}/status?lines=`. The server keeps the status of each action it started in this process.
    public func actionStatus(_ name: String, lines: Int = 200) async throws -> ServerActionStatus {
        try await get(
            "/api/actions/" + restPathSegment(name) + "/status",
            query: [URLQueryItem(name: "lines", value: String(lines))])
    }
}

/// Polls a background action until its process ends.
public struct ServerActionPoller: Sendable {
    /// Wait between two polls.
    public var interval: Duration
    /// Polls before giving up with ``ServerActionTimeout``.
    public var maxPolls: Int

    /// Creates a poller. The defaults poll every two seconds for about ten minutes.
    public init(interval: Duration = .seconds(2), maxPolls: Int = 300) {
        self.interval = interval
        self.maxPolls = maxPolls
    }

    /// Polls `name` until it stops running and returns its last status. `update` hears every status, for a live log tail.
    public func finish(
        _ name: String, rest: RESTClient, update: @Sendable (ServerActionStatus) async -> Void = { _ in }
    ) async throws -> ServerActionStatus {
        var polls = 0
        while true {
            let status = try await rest.actionStatus(name)
            await update(status)
            if !status.isRunning { return status }
            polls += 1
            if polls >= maxPolls { throw ServerActionTimeout(name: name) }
            try await Task.sleep(for: interval)
        }
    }
}
