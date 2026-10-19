import Foundation

/// Where the memory screen reads from: one server, and the profile it works as (WP-41, WP-52).
public struct JourneySource: Sendable {
    /// Names the server. A different id means a different graph, so the screen starts over.
    public var id: String
    /// The server's name, for messages.
    public var name: String
    /// The server calls.
    public var backend: any JourneyBackend
    /// The profile the calls carry right now, or nil for the server's own. The screen asks every few seconds and
    /// reloads when the answer changes, because every profile has its own graph.
    public var currentProfile: @Sendable () async -> String?

    /// Creates a source.
    public init(
        id: String, name: String, backend: any JourneyBackend,
        currentProfile: @escaping @Sendable () async -> String? = { nil }
    ) {
        self.id = id
        self.name = name
        self.backend = backend
        self.currentProfile = currentProfile
    }

    /// A source over the made-up sample graph, for previews, snapshots and tests. Every call makes a fresh backend, so
    /// edits in one preview never show up in another.
    public static func sample(name: String = "Preview server") -> JourneySource {
        JourneySource(id: "sample", name: name, backend: SampleJourneyBackend())
    }
}
