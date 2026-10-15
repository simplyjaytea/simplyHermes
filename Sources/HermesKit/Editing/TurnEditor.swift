import Foundation

/// What the editor needs from a live session. ``GatewayClient`` conforms; tests use a fake.
public protocol PromptSession: Sendable {
    /// Calls `prompt.submit`.
    func submitPrompt(_ params: PromptSubmitParams) async throws -> PromptSubmitResult
    /// Calls `session.interrupt`.
    func interruptSession(_ params: SessionInterruptParams) async throws
}

extension GatewayClient: PromptSession {
    /// Calls `prompt.submit`.
    public func submitPrompt(_ params: PromptSubmitParams) async throws -> PromptSubmitResult {
        try await call("prompt.submit", params: params)
    }

    /// Calls `session.interrupt`.
    public func interruptSession(_ params: SessionInterruptParams) async throws {
        let _: SessionInterruptResult = try await call("session.interrupt", params: params)
    }
}

/// What a rewind would archive, worked out from the local transcript before anything is sent.
public struct RewindImpact: Sendable, Equatable {
    /// Rows from the cut on, tool calls included.
    public var archivedItems: Int
    /// User turns from the cut on (the one being edited counts).
    public var archivedUserTurns: Int
    /// True when nothing would be left before the cut.
    public var emptiesTranscript: Bool

    /// Creates an impact.
    public init(archivedItems: Int, archivedUserTurns: Int, emptiesTranscript: Bool) {
        self.archivedItems = archivedItems
        self.archivedUserTurns = archivedUserTurns
        self.emptiesTranscript = emptiesTranscript
    }

    /// The impact of cutting `state` at the user row `rowID`. Nil when no user row has that id.
    public static func of(_ state: TranscriptState, fromRowID rowID: Int) -> RewindImpact? {
        guard
            let start = state.items.firstIndex(where: {
                if case .user(let entry) = $0.content { return entry.rowID == rowID }
                return false
            })
        else { return nil }
        let tail = state.items[start...]
        let turns = tail.filter {
            if case .user(let entry) = $0.content { return entry.displayKind == nil }
            return false
        }.count
        return RewindImpact(archivedItems: tail.count, archivedUserTurns: turns, emptiesTranscript: start == 0)
    }
}

/// A question the user must answer before an edit goes ahead.
public enum TurnEditConfirmation: Sendable, Equatable {
    /// The cut would erase the whole transcript (`4028`).
    case emptiesTranscript
    /// More than one user turn would be archived. The counts come from the server when it sent them, else from
    /// the local transcript.
    case deepCut(archivedMessages: Int?, archivedUserTurns: Int?)
}

/// Confirmations the user has already given.
public struct TurnEditConsent: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    /// The user accepted erasing the whole transcript.
    public static let emptiesTranscript = TurnEditConsent(rawValue: 1)
    /// The user accepted archiving several turns.
    public static let deepCut = TurnEditConsent(rawValue: 2)
}

/// How an edit, rewind or regenerate ended.
public enum TurnEditOutcome: Sendable, Equatable {
    /// The server accepted it. The result carries the survivor row ids to rebind.
    case done(PromptSubmitResult)
    /// Ask the user, then call again with the matching ``TurnEditConsent``.
    case needsConfirmation(TurnEditConfirmation)
    /// The row is no longer in the server's history (`4018`; there is no fallback). Reload the history.
    case stale(userTurnCount: Int?)
    /// The session stayed busy after an interrupt (`4009`).
    case busy
    /// Anything else, including `4004` and `4029`, which mean the client sent something it should not have.
    case failed(RPCError)
}

/// Edit, rewind and regenerate on top of `prompt.submit` with a truncation (plan section 2.2).
///
/// Always sends the row id (an ordinal alone is refused with `4004`) and `confirm_truncate`. A deep cut is
/// always put to the user first, even though this server does not enforce `4033` yet.
public struct TurnEditor: Sendable {
    private let session: any PromptSession
    private let sessionID: String
    private let profile: String?

    /// Creates an editor for one live session.
    public init(session: any PromptSession, sessionID: String, profile: String? = nil) {
        self.session = session
        self.sessionID = sessionID
        self.profile = profile
    }

    /// Replaces the user turn at `rowID` (and everything after it) with `text`.
    ///
    /// `impact` is ``RewindImpact/of(_:fromRowID:)`` for the current transcript; it lets the deep and empty cuts
    /// be put to the user before any request. Pass nil to rely on the server's answers alone.
    public func edit(
        text: String, fromRowID rowID: Int, impact: RewindImpact? = nil, consent: TurnEditConsent = []
    ) async -> TurnEditOutcome {
        if let impact {
            if impact.emptiesTranscript, !consent.contains(.emptiesTranscript) {
                return .needsConfirmation(.emptiesTranscript)
            }
            if impact.archivedUserTurns > 1, !consent.contains(.deepCut) {
                return .needsConfirmation(
                    .deepCut(archivedMessages: impact.archivedItems, archivedUserTurns: impact.archivedUserTurns))
            }
        }

        var interrupted = false
        while true {
            let truncate = PromptTruncate(
                truncateBeforeRowID: rowID,
                confirmEmptyTruncate: consent.contains(.emptiesTranscript) ? true : nil,
                confirmDeepTruncate: consent.contains(.deepCut) ? true : nil)
            let params = PromptSubmitParams(sessionID: sessionID, text: text, profile: profile, truncate: truncate)
            do {
                return .done(try await session.submitPrompt(params))
            } catch let error as RPCError {
                switch error.code {
                case HermesErrorCode.sessionBusy where !interrupted:
                    interrupted = true
                    do {
                        try await session.interruptSession(
                            SessionInterruptParams(sessionID: sessionID, profile: profile))
                    } catch let failure as RPCError {
                        return .failed(failure)
                    } catch {
                        return .failed(Self.transportError(error))
                    }
                case HermesErrorCode.sessionBusy:
                    return .busy
                case HermesErrorCode.targetTurnMissing:
                    return .stale(userTurnCount: error.data?["user_turn_count"]?.intValue)
                case HermesErrorCode.truncateWouldEmptyTranscript where !consent.contains(.emptiesTranscript):
                    return .needsConfirmation(.emptiesTranscript)
                case HermesErrorCode.deepTruncateUnconfirmed where !consent.contains(.deepCut):
                    return .needsConfirmation(
                        .deepCut(
                            archivedMessages: error.data?["archived_messages"]?.intValue,
                            archivedUserTurns: error.data?["archived_user_turns"]?.intValue))
                default:
                    return .failed(error)
                }
            } catch {
                return .failed(Self.transportError(error))
            }
        }
    }

    /// Runs the last user turn again: edits it with its own text. Nil when the transcript has no stored user turn.
    public func regenerate(state: TranscriptState, consent: TurnEditConsent = []) async -> TurnEditOutcome? {
        guard
            let last = state.items.last(where: {
                if case .user(let entry) = $0.content { return entry.rowID != nil && entry.displayKind == nil }
                return false
            }),
            case .user(let entry) = last.content, let rowID = entry.rowID
        else { return nil }
        return await edit(
            text: entry.text, fromRowID: rowID, impact: RewindImpact.of(state, fromRowID: rowID), consent: consent)
    }

    private static func transportError(_ error: any Error) -> RPCError {
        RPCError(code: HermesErrorCode.internalError, message: "\(error)")
    }
}
