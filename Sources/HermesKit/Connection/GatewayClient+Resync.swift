import Foundation

/// Re-attaching tracked sessions after a reconnect: `session.activate`, or `session.resume` when the live id is gone,
/// then replaying what was missed. Kept apart from ``GatewayClient`` so that actor stays under the lint size limit.
extension GatewayClient {
    func resync(liveID: String, forceCold: Bool) async {
        guard let tracked = sessions[liveID] else { return }
        resyncing.insert(liveID)
        defer {
            resyncing.remove(liveID)
        }
        do {
            var cold = forceCold
            var attach: SessionAttachResult?
            if !cold {
                do {
                    attach = try await callAttach(
                        "session.activate", SessionActivateParams(sessionID: liveID, profile: tracked.profile))
                } catch let error as RPCError where Self.isSessionNotFound(error) {
                    cold = true
                }
            }
            if cold {
                let result = try await callAttach(
                    "session.resume", SessionResumeParams(sessionID: tracked.storedID, profile: tracked.profile))
                rekey(
                    old: liveID, new: result.sessionID, storedID: result.storedSessionID ?? tracked.storedID,
                    profile: tracked.profile)
                buffered[liveID] = nil
                emit(.sessionReattached(oldLiveID: liveID, result: result, how: .cold))
                resyncing.insert(result.sessionID)
                flush(liveID: result.sessionID)
                return
            }
            let since: SessionEventsSinceResult = try await callTyped(
                "session.events.since",
                SessionEventsSinceParams(
                    sessionID: liveID, profile: tracked.profile, lastSeen: sessions[liveID]?.watermark))
            replay(since, liveID: liveID)
            if let attach { emit(.sessionReattached(oldLiveID: liveID, result: attach, how: .live)) }
            flush(liveID: liveID)
        } catch {
            buffered[liveID] = nil
            emit(.resyncFailed(sessionID: liveID, message: "\(error)"))
        }
    }

    private func replay(_ since: SessionEventsSinceResult, liveID: String) {
        if since.truncated {
            if var tracked = sessions[liveID] {
                tracked.watermark = since.latestSeq
                sessions[liveID] = tracked
            }
            emit(.replayTruncated(sessionID: liveID, latestSeq: since.latestSeq))
        } else {
            for envelope in since.events { deliver(envelope, replayed: true) }
        }
        for request in since.openRequests {
            emit(.openRequestReplayed(sessionID: liveID, request: request))
        }
    }

    private func flush(liveID: String) {
        let queued = buffered.removeValue(forKey: liveID) ?? []
        resyncing.remove(liveID)
        for envelope in queued { deliver(envelope, replayed: false) }
    }

    private func rekey(old: String, new: String, storedID: String, profile: String?) {
        sessions[old] = nil
        sessions[new] = GatewayTrackedSession(liveID: new, storedID: storedID, watermark: nil, profile: profile)
    }

    private static func isSessionNotFound(_ error: RPCError) -> Bool {
        error.code == HermesErrorCode.sessionNotFound || error.code == HermesErrorCode.sessionNotFoundAlternate
    }

    private func callAttach(_ method: String, _ params: some Encodable & Sendable) async throws -> SessionAttachResult {
        try await callTyped(method, params)
    }

    private func callTyped<Params: Encodable & Sendable, Result: Decodable & Sendable>(
        _ method: String, _ params: Params
    ) async throws -> Result {
        let response = try await sendRaw(method: method, params: try JSONValue(encoding: params), timeout: nil)
        if let error = response.error { throw error }
        guard let value = try response.decodeResult(Result.self) else {
            throw DecodingError.valueNotFound(
                Result.self, .init(codingPath: [], debugDescription: "response to \(method) has no result"))
        }
        return value
    }
}
