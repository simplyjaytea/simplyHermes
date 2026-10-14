import Foundation
import HermesKit
import Testing

private let endpoint = HermesEndpoint(string: "https://hermes.example")!

private struct Rig {
    let client: GatewayClient
    let transport = FakeTransport()
    let clock = ManualClock()
    let log: EventLog

    init() async {
        var config = GatewayClientConfig()
        config.reconnect = ReconnectPolicy(jitter: { $0 })
        client = GatewayClient(
            endpoint: endpoint, transport: transport, credentials: { _ in .ticket("t") }, clock: clock, config: config)
        log = EventLog(await client.events())
    }

    /// Connects the first socket, tracks session `s1` at watermark 5, then drops it and reconnects on `second`.
    func dropAndReconnect(first: FakeSocket, second: FakeSocket, watermark: Int = 5) async throws {
        first.serve()
        transport.enqueue(.socket(first))
        await client.start()
        try await waitUntil("first connected") { log.states.contains(.connected) }
        await client.track(liveID: "s1", storedID: "stored-1", watermark: watermark)
        transport.enqueue(.socket(second))
        first.drop()
        try await waitUntil("waiting") { !log.waits.isEmpty }
        await clock.advance(by: 1, step: 0.5)
    }
}

@Suite(.serialized) struct GatewayResyncTests {
    @Test func liveReattachReplaysOnlyEventsAfterTheWatermark() async throws {
        let rig = await Rig()
        let first = FakeSocket()
        let second = FakeSocket()
        second.serve { frame in
            guard let id = frame.id else { return [] }
            switch frame.method {
            case "session.activate": return [Frames.result(id: id, Frames.attach(live: "s1", stored: "stored-1"))]
            case "session.events.since":
                let events = [4, 5, 6, 7].map { Frames.rawEvent(session: "s1", seq: $0) }
                return [Frames.result(id: id, Frames.since(events: events, latest: 7))]
            default: return []
            }
        }
        try await rig.dropAndReconnect(first: first, second: second)
        try await waitUntil("replayed") { rig.log.deliveredSeqs == [6, 7] }
        let since = second.requests("session.events.since").first
        #expect(since?.params?["last_seen"] as? Int == 5)
        #expect(await rig.client.watermark(liveID: "s1") == 7)
        let reattached = rig.log.all.contains {
            if case .sessionReattached(_, _, .live) = $0 { true } else { false }
        }
        #expect(reattached)
        await rig.client.stop()
    }

    @Test func liveEventsDuringResyncAreBufferedAndDeduplicated() async throws {
        let rig = await Rig()
        let first = FakeSocket()
        let second = FakeSocket()
        second.serve { frame in
            guard let id = frame.id else { return [] }
            switch frame.method {
            case "session.activate":
                // A live event overtakes the replay: seq 7 is also in the replay result.
                return [
                    Frames.delta(session: "s1", seq: 7), Frames.delta(session: "s1", seq: 8),
                    Frames.result(id: id, Frames.attach(live: "s1", stored: "stored-1")),
                ]
            case "session.events.since":
                let events = [6, 7].map { Frames.rawEvent(session: "s1", seq: $0) }
                return [Frames.result(id: id, Frames.since(events: events, latest: 7))]
            default: return []
            }
        }
        try await rig.dropAndReconnect(first: first, second: second)
        try await waitUntil("all delivered") { rig.log.deliveredSeqs.count == 3 }
        #expect(rig.log.deliveredSeqs == [6, 7, 8])
        await rig.client.stop()
    }

    @Test func truncatedReplayPaintsNoGapAndAdvancesTheWatermark() async throws {
        let rig = await Rig()
        let first = FakeSocket()
        let second = FakeSocket()
        second.serve { frame in
            guard let id = frame.id else { return [] }
            switch frame.method {
            case "session.activate": return [Frames.result(id: id, Frames.attach(live: "s1", stored: "stored-1"))]
            case "session.events.since":
                return [Frames.result(id: id, Frames.since(events: [], latest: 900, truncated: true))]
            default: return []
            }
        }
        try await rig.dropAndReconnect(first: first, second: second)
        try await waitUntil("truncated") {
            rig.log.all.contains { if case .replayTruncated("s1", 900) = $0 { true } else { false } }
        }
        #expect(rig.log.deliveredSeqs.isEmpty)
        #expect(await rig.client.watermark(liveID: "s1") == 900)
        await rig.client.stop()
    }

    @Test func reapedSessionIsResumedColdAndRekeyed() async throws {
        let rig = await Rig()
        let first = FakeSocket()
        let second = FakeSocket()
        second.serve { frame in
            guard let id = frame.id else { return [] }
            switch frame.method {
            case "session.activate": return [Frames.error(id: id, code: 4001, message: "session not found")]
            case "session.resume": return [Frames.result(id: id, Frames.attach(live: "s2", stored: "stored-1"))]
            default: return []
            }
        }
        try await rig.dropAndReconnect(first: first, second: second)
        try await waitUntil("cold") {
            rig.log.all.contains { if case .sessionReattached("s1", _, .cold) = $0 { true } else { false } }
        }
        #expect(second.requests("session.resume").first?.params?["session_id"] as? String == "stored-1")
        #expect(second.requests("session.events.since").isEmpty)
        #expect(await rig.client.watermark(liveID: "s2") == nil)
        // Events for the new live id flow from seq 1.
        second.push(Frames.delta(session: "s2", seq: 1))
        try await waitUntil("event") { rig.log.deliveredSeqs == [1] }
        await rig.client.stop()
    }

    @Test func alternateNotFoundCodeAlsoFallsBackToResume() async throws {
        let rig = await Rig()
        let first = FakeSocket()
        let second = FakeSocket()
        second.serve { frame in
            guard let id = frame.id else { return [] }
            switch frame.method {
            case "session.activate": return [Frames.error(id: id, code: 4007)]
            case "session.resume": return [Frames.result(id: id, Frames.attach(live: "s9", stored: "stored-1"))]
            default: return []
            }
        }
        try await rig.dropAndReconnect(first: first, second: second)
        try await waitUntil("cold") {
            rig.log.all.contains { if case .sessionReattached(_, _, .cold) = $0 { true } else { false } }
        }
        await rig.client.stop()
    }

    @Test func serverRestartRebuildsEverySessionCold() async throws {
        let rig = await Rig()
        let first = FakeSocket()
        let second = FakeSocket()
        second.serve(epoch: "epoch-2") { frame in
            guard let id = frame.id else { return [] }
            if frame.method == "session.resume" {
                return [Frames.result(id: id, Frames.attach(live: "s7", stored: "stored-1"))]
            }
            return []
        }
        try await rig.dropAndReconnect(first: first, second: second)
        try await waitUntil("restart") { rig.log.all.contains(.serverRestarted) }
        try await waitUntil("cold") { !second.requests("session.resume").isEmpty }
        #expect(second.requests("session.activate").isEmpty)
        await rig.client.stop()
    }

    @Test func openRequestsAreRedelivered() async throws {
        let rig = await Rig()
        let first = FakeSocket()
        let second = FakeSocket()
        second.serve { frame in
            guard let id = frame.id else { return [] }
            switch frame.method {
            case "session.activate": return [Frames.result(id: id, Frames.attach(live: "s1", stored: "stored-1"))]
            case "session.events.since":
                let open = #"[{"id":"srq-9","method":"approval","params":{"command":"rm x"}}]"#
                return [Frames.result(id: id, Frames.since(events: [], latest: 5, open: open))]
            default: return []
            }
        }
        try await rig.dropAndReconnect(first: first, second: second)
        try await waitUntil("open request") {
            rig.log.all.contains {
                if case .openRequestReplayed("s1", let entry) = $0 { entry.id == "srq-9" } else { false }
            }
        }
        await rig.client.stop()
    }

    @Test func takeoverMarksSessionReclaimedAndSkipsItOnReconnect() async throws {
        let rig = await Rig()
        let first = FakeSocket()
        first.serve()
        rig.transport.enqueue(.socket(first))
        await rig.client.start()
        try await waitUntil("connected") { rig.log.states.contains(.connected) }
        await rig.client.track(liveID: "s1", storedID: "stored-1", watermark: 2)
        first.push(
            #"{"jsonrpc":"2.0","method":"event","params":{"type":"session.reclaimed","session_id":"s1","#
                + #""payload":{"session_id":"s1","stored_session_id":"stored-1","reason":"takeover"}}}"#)
        try await waitUntil("reclaimed") {
            rig.log.all.contains { if case .sessionReclaimed("s1", _, "takeover") = $0 { true } else { false } }
        }
        let second = FakeSocket()
        second.serve()
        rig.transport.enqueue(.socket(second))
        first.drop()
        try await waitUntil("waiting") { !rig.log.waits.isEmpty }
        await rig.clock.advance(by: 1, step: 0.5)
        try await waitUntil("reconnected") { rig.log.states.filter { $0 == .connected }.count == 2 }
        #expect(second.requests("session.activate").isEmpty)
        #expect(second.requests("session.resume").isEmpty)
        await rig.client.stop()
    }

    @Test func resyncFailureIsReported() async throws {
        let rig = await Rig()
        let first = FakeSocket()
        let second = FakeSocket()
        second.serve { frame in
            guard let id = frame.id else { return [] }
            if frame.method == "session.activate" { return [Frames.error(id: id, code: -32603, message: "kaput")] }
            return []
        }
        try await rig.dropAndReconnect(first: first, second: second)
        try await waitUntil("failure") {
            rig.log.all.contains { if case .resyncFailed("s1", _) = $0 { true } else { false } }
        }
        await rig.client.stop()
    }
}
