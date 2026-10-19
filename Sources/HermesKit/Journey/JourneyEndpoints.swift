import Foundation

/// `PUT /api/learning/node` body. The profile rides in the body and in the query: a shared-backend client may scope
/// a call by either, and the server honours both.
struct LearningNodeEdit: Encodable, Sendable {
    var id: String
    var content: String
    var profile: String?
}

/// `DELETE /api/learning/node` body.
struct LearningNodeRef: Encodable, Sendable {
    var id: String
    var profile: String?
}

extension RESTClient {
    /// `GET /api/learning/graph`: the learned skills and memory chunks of the active profile.
    public func learningGraph() async throws -> JourneyGraph {
        try await get("/api/learning/graph")
    }

    /// `GET /api/learning/node`: the full text of a node, for the edit prefill.
    public func learningNode(id: String) async throws -> JourneyNodeDetail {
        try await get("/api/learning/node", query: [URLQueryItem(name: "id", value: id)])
    }

    /// `PUT /api/learning/node`: rewrites a node. For a skill `content` is the whole `SKILL.md`, for a memory the raw
    /// chunk. The server refuses text it cannot use with a `4xx` and its reason in ``RESTError/http(status:detail:)``.
    @discardableResult
    public func updateLearningNode(id: String, content: String) async throws -> JourneyMutationResult {
        let response: HTTPResponse = try await send(
            "PUT", "/api/learning/node", body: LearningNodeEdit(id: id, content: content, profile: profile))
        return try JourneyMutationResult(body: response.body).accepted(status: response.status)
    }

    /// `DELETE /api/learning/node`: archives a skill (it can be restored on the server) or removes a memory chunk.
    /// The server refuses to delete a pinned skill.
    @discardableResult
    public func deleteLearningNode(id: String) async throws -> JourneyMutationResult {
        let response: HTTPResponse = try await send(
            "DELETE", "/api/learning/node", body: LearningNodeRef(id: id, profile: profile))
        return try JourneyMutationResult(body: response.body).accepted(status: response.status)
    }
}

extension JourneyMutationResult {
    /// The result itself, or an error when a success status carries `"ok": false`.
    func accepted(status: Int) throws -> JourneyMutationResult {
        guard ok == false else { return self }
        throw RESTError.http(status: status, detail: message ?? "The server did not accept the change.")
    }
}

/// The server calls the memory screen needs. ``RESTClient`` conforms; previews and tests use a fake.
public protocol JourneyBackend: Sendable {
    /// `GET /api/learning/graph`.
    func learningGraph() async throws -> JourneyGraph
    /// `GET /api/learning/node`.
    func learningNode(id: String) async throws -> JourneyNodeDetail
    /// `PUT /api/learning/node`.
    func updateLearningNode(id: String, content: String) async throws -> JourneyMutationResult
    /// `DELETE /api/learning/node`.
    func deleteLearningNode(id: String) async throws -> JourneyMutationResult
}

extension RESTClient: JourneyBackend {}

/// A ``JourneyBackend`` for a saved connection. It asks the ``ConnectionManager`` for the signed-in REST client on
/// every call, so the screen connects on demand and every call carries the profile the user chose (WP-41).
public struct ManagedJourneyBackend: JourneyBackend {
    private let manager: ConnectionManager
    private let connection: ServerConnection

    /// Creates a backend for `connection`.
    public init(manager: ConnectionManager, connection: ServerConnection) {
        self.manager = manager
        self.connection = connection
    }

    /// Connects on demand and returns the REST client. Throws ``ConnectionUnavailable`` when it cannot connect.
    private func rest() async throws -> RESTClient {
        _ = try await manager.client(for: connection)
        guard let rest = await manager.rest(for: connection.id) else {
            throw ConnectionUnavailable(phase: await manager.phase(of: connection.id))
        }
        return rest
    }

    public func learningGraph() async throws -> JourneyGraph {
        try await rest().learningGraph()
    }

    public func learningNode(id: String) async throws -> JourneyNodeDetail {
        try await rest().learningNode(id: id)
    }

    public func updateLearningNode(id: String, content: String) async throws -> JourneyMutationResult {
        try await rest().updateLearningNode(id: id, content: content)
    }

    public func deleteLearningNode(id: String) async throws -> JourneyMutationResult {
        try await rest().deleteLearningNode(id: id)
    }
}
