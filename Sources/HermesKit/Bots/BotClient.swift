import Foundation

/// The calls the Bots feature makes. `GatewayClient` conforms; tests use a fake.
public protocol BotGateway: Sendable {
    func call<Result: Decodable & Sendable>(
        _ method: String, params: (any Encodable & Sendable)?, as type: Result.Type
    ) async throws -> Result
}

extension GatewayClient: BotGateway {
    public func call<Result: Decodable & Sendable>(
        _ method: String, params: (any Encodable & Sendable)?, as type: Result.Type
    ) async throws -> Result {
        try await call(method, params: params, as: type, timeout: nil)
    }
}

public enum BotError: Error, Sendable, Equatable {
    case profileNotFound(String)
    /// The gateway answered without saying the namespace was written.
    case metaNotSaved(String)
    /// Another writer changed the namespace on every attempt.
    case metaConflict(String)
    /// The `ui_meta` payload is over the server's limit. Nothing was sent.
    case metaTooLarge
    case invalidDraft([NewAgentDraft.Problem])
    /// The roster says a Bot Chat exists, but the lookup found none. Nothing was created.
    case chatInconsistent(String)
    /// `profiles.configure` did not report the role (the profile description) as written.
    case roleNotSaved(String)
}

/// The rich roster of the connected gateway, from `profiles.list {include_sessions: true}`.
public struct BotRichRoster: Sendable, Equatable {
    public var rows: [BotRosterRow]
    public var installID: String
    public var botModeProtocol: Bool
}

/// `session.list` rows for the Bot Chat lookup.
public struct BotChatListResult: Sendable, Equatable, Codable {
    public var sessions: [BotChatRow]
}

/// `session.create` for a Bot Chat: hidden, following the profile's config, not yet materialized.
public struct BotSessionCreateParams: Sendable, Equatable, Codable {
    public var profile: String
    public var title: String
    public var hidden: Bool
    public var followProfileConfig: Bool

    enum CodingKeys: String, CodingKey {
        case profile, title, hidden
        case followProfileConfig = "follow_profile_config"
    }
}

public struct BotSessionCreateResult: Sendable, Equatable, Codable {
    public var sessionID: String
    public var storedSessionID: String?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case storedSessionID = "stored_session_id"
    }
}

/// `session.title`: materializes the lazy Bot Chat row.
public struct BotSessionTitleParams: Sendable, Equatable, Codable {
    public var sessionID: String
    public var title: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case title
    }
}

/// Bot roster, Bot Chat and New Agent calls over one gateway (plan 2.5, WP-42).
public struct BotClient: Sendable {
    /// Read-modify-write attempts before a namespace write gives up (Desktop's `BOT_META_CAS_ATTEMPTS`).
    public static let maxAttempts = 3

    public let gateway: any BotGateway

    public init(gateway: any BotGateway) {
        self.gateway = gateway
    }

    /// The connected gateway's bots, with live chat, activity and look.
    public func richRoster() async throws -> BotRichRoster {
        let result = try await gateway.call(
            "profiles.list", params: ProfilesListParams(includeSessions: true), as: ProfilesListResult.self)
        return BotRichRoster(
            rows: result.profiles.map(BotRosterRow.init(rich:)), installID: result.installID,
            botModeProtocol: result.botModeProtocol)
    }

    /// Replaces one `ui_meta` namespace: reads it, applies `change`, and writes it back with a compare-and-swap on the
    /// revision it read. A conflict reads again, up to ``maxAttempts`` times.
    public func updateNamespace(
        profile: String, namespace: String, _ change: (inout BotMetaObject) -> Void
    ) async throws {
        for _ in 0..<Self.maxAttempts {
            let list = try await gateway.call(
                "profiles.list", params: ProfilesListParams(includeSessions: false), as: ProfilesListResult.self)
            guard let row = list.profiles.first(where: { $0.name == profile }) else {
                throw BotError.profileNotFound(profile)
            }
            var object = BotMetaObject(row.uiMeta?[namespace])
            change(&object)
            // Revisions missing as a whole means an older gateway: write without the compare-and-swap.
            let expected = row.uiMetaRevisions.map { $0[namespace] ?? 0 }
            let payload = BotMetaWrite.payload([
                BotMetaWrite(namespace: namespace, value: object.writable, expectedRevision: expected)
            ])
            let encoded = try JSONEncoder().encode(payload.uiMeta)
            guard encoded.count <= BotMetaNamespace.maxPayloadBytes else { throw BotError.metaTooLarge }
            let params = ProfilesConfigureParams(
                name: profile, uiMeta: payload.uiMeta, uiMetaExpectedRevisions: payload.expected)
            let result = try await gateway.call(
                "profiles.configure", params: params, as: ProfilesConfigureResult.self)
            if let conflicts = result.applied.uiMetaConflicts, !conflicts.isEmpty { continue }
            guard result.applied.uiMeta == true else { throw BotError.metaNotSaved(profile) }
            return
        }
        throw BotError.metaConflict(profile)
    }

    /// Finds the profile's Bot Chat. Fails closed: a lookup that comes back empty where the roster says a chat exists
    /// throws, and nothing is created.
    public func findBotChat(profile: String, rosterKnowsChat: Bool) async throws -> BotChatLookup {
        let result = try await gateway.call(
            "session.list",
            params: SessionListParams(profile: profile, title: BotChat.title, limit: 200, includeHidden: true),
            as: BotChatListResult.self)
        return BotChatLookup.resolve(result.sessions, rosterKnowsChat: rosterKnowsChat)
    }

    /// Creates the profile's Bot Chat, hidden, and returns the id to open. If another writer took the title first, the
    /// existing chat is adopted and this attempt's session is left hidden and unused.
    public func createBotChat(profile: String) async throws -> String {
        let created = try await gateway.call(
            "session.create",
            params: BotSessionCreateParams(
                profile: profile, title: BotChat.title, hidden: true, followProfileConfig: true),
            as: BotSessionCreateResult.self)
        do {
            _ = try await gateway.call(
                "session.title",
                params: BotSessionTitleParams(sessionID: created.sessionID, title: BotChat.title),
                as: JSONValue.self)
        } catch let error as RPCError where error.code == 4022 {
            switch try await findBotChat(profile: profile, rosterKnowsChat: true) {
            case .found(let openID, _): return openID
            case .none, .inconsistent: throw BotError.chatInconsistent(profile)
            }
        }
        return created.storedSessionID ?? created.sessionID
    }

    /// What `createAgent` made. The profile exists even when `lookSaved` is false.
    public struct CreatedAgent: Sendable, Equatable {
        public var profile: String
        /// False when the title or avatar did not save. The bot can be edited later.
        public var lookSaved: Bool

        public init(profile: String, lookSaved: Bool) {
            self.profile = profile
            self.lookSaved = lookSaved
        }
    }

    /// Creates an agent: the profile, its staged skills, toolsets and MCP servers, then its title, look and avatar. The
    /// Bot Chat is created when the bot is first opened, not here. A failed look write does not fail the call: the
    /// profile already exists, and a retry would only hit `nameTaken`.
    public func createAgent(
        _ draft: NewAgentDraft, existingProfiles: Set<String>, now: Date = Date()
    ) async throws -> CreatedAgent {
        let problems = draft.problems(existingProfiles: existingProfiles)
        guard problems.isEmpty else { throw BotError.invalidDraft(problems) }
        let created = try await gateway.call(
            "profiles.create", params: draft.createParams(), as: ProfilesCreateResult.self)
        let name = created.name
        // The staged lists are best effort, as Desktop treats them: the profile already exists.
        if let staged = draft.stagedConfigureParams() {
            _ = try? await gateway.call("profiles.configure", params: staged, as: ProfilesConfigureResult.self)
        }
        do {
            let shownTitle = draft.shownTitle
            let createdMillis = Int(now.timeIntervalSince1970 * 1000)
            try await updateNamespace(profile: name, namespace: BotMetaNamespace.desktop) { meta in
                meta.title = shownTitle.isEmpty ? nil : shownTitle
                meta.createdAt = createdMillis
                meta.setValue("shape", .string("blobatar"))
                meta.setValue("imageKind", .string("shape"))
            }
            if let avatar = draft.avatar {
                try await updateNamespace(profile: name, namespace: BotMetaNamespace.app) { object in
                    object = BotAppLook(avatar: avatar).applied(to: object)
                }
            }
            return CreatedAgent(profile: name, lookSaved: true)
        } catch {
            return CreatedAgent(profile: name, lookSaved: false)
        }
    }

    /// Sets the role text, which is the profile's description. Desktop writes it the same way.
    public func setRole(profile: String, role: String) async throws {
        let result = try await gateway.call(
            "profiles.configure", params: ProfilesConfigureParams(name: profile, description: role),
            as: ProfilesConfigureResult.self)
        guard result.applied.description == true else { throw BotError.roleNotSaved(profile) }
    }

    /// Roster rows from REST `/api/profiles`, for a gateway that is not connected. `default` is added when absent.
    public static func restRows(_ profiles: [HermesProfile]) -> [BotRosterRow] {
        var rows = profiles.map { profile in
            BotRosterRow(
                profile: profile.name, isDefault: profile.isDefault ?? false,
                backendTitle: BotNaming.nonEmpty(profile.botTitle),
                displayName: BotNaming.nonEmpty(profile.displayName),
                description: profile.description, model: profile.model, provider: profile.provider)
        }
        if !rows.contains(where: { $0.profile == "default" }) {
            rows.insert(BotRosterRow(profile: "default", isDefault: true), at: 0)
        }
        return rows
    }
}

extension BotRosterRow {
    /// A rich row from `profiles.list`. The Bot Chat and last activity come from whichever of the chat and the last session
    /// is newer, ties going to the chat.
    public init(rich row: ProfileRow) {
        let canonical = row.canonicalSession
        let lastSession = row.lastSession
        let canonicalActive = canonical?["last_active"]?.doubleValue
        let sessionActive = lastSession?["last_active"]?.doubleValue
        let lastActive: Double?
        if let canonicalActive, let sessionActive {
            lastActive = canonicalActive >= sessionActive ? canonicalActive : sessionActive
        } else {
            lastActive = canonicalActive ?? sessionActive
        }
        self.init(
            profile: row.name, isDefault: row.isDefault ?? false, backendTitle: nil,
            displayName: BotNaming.nonEmpty(row.displayName), description: row.description, model: row.model,
            provider: row.provider, meta: BotMetaObject(row.uiMeta?[BotMetaNamespace.desktop]),
            appLook: BotAppLook(object: BotMetaObject(row.uiMeta?[BotMetaNamespace.app])),
            canonicalSessionID: canonical?["resolved_id"]?.stringValue ?? canonical?["id"]?.stringValue,
            lastActive: lastActive, workerActiveAt: row.workerSession?["last_active"]?.doubleValue,
            preview: canonical?["preview"]?.stringValue)
    }
}
