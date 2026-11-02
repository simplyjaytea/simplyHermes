import Foundation
import Testing

@testable import HermesKit

// G1: the message-loss model test (Shared/simplyhermes-gilfoyle-proposals-2026-11-02.md). Fixed seeds for the
// orderings that broke before, then a seeded random walk. The rule under test: from the moment a message is saved, it
// is delivered, waiting, visibly failed or deleted by the user. Never gone, never stuck sending after a relaunch, and
// sent to the server again only when the app died after the server got it (prompt.submit has no client id).

/// What the model server does with the next delivery.
enum ServerReply: Sendable, Equatable {
    /// Takes the message and acknowledges it.
    case acknowledge
    /// Busy or not live: the message stays pending.
    case deferIt
    /// Refuses the prompt.
    case refuse
    /// The app dies before the request leaves the phone. The server never sees it.
    case crashBeforeReceipt
    /// The app dies after the server took the message, before the acknowledgement was recorded.
    case crashAfterReceipt
}

/// The server side of the model. It records every delivery it receives, by record id. A crash reply never returns:
/// the drain hangs there like a killed process, and the test throws the drainer away.
actor ModelServer: OutboxSubmitter {
    private var replies: [ServerReply]
    private(set) var received: [UUID] = []
    private(set) var crashed = false
    /// Messages the server took while the app died before recording the acknowledgement.
    private(set) var lostAcks: [UUID: Int] = [:]

    init(_ replies: [ServerReply] = []) { self.replies = replies }

    func script(_ next: [ServerReply]) {
        replies = next
        crashed = false
    }

    func deliver(_ record: OutboundRecord) async -> SubmitOutcome {
        let reply = replies.isEmpty ? .acknowledge : replies.removeFirst()
        switch reply {
        case .acknowledge:
            received.append(record.id)
            return .acknowledged
        case .deferIt:
            return .deferred
        case .refuse:
            return .failed("refused")
        case .crashBeforeReceipt:
            return await hang()
        case .crashAfterReceipt:
            received.append(record.id)
            lostAcks[record.id, default: 0] += 1
            return await hang()
        }
    }

    /// Never returns until the task is cancelled; then reports `.deferred`, which a dead process would never write.
    /// The test only cancels after it has stopped looking at this drainer.
    private func hang() async -> SubmitOutcome {
        crashed = true
        while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(1)) }
        return .deferred
    }

    func deliveries(of id: UUID) -> Int { received.filter { $0 == id }.count }

    func lostAcks(of id: UUID) -> Int { lostAcks[id] ?? 0 }
}

/// One phone: the cache file, the current "process" (store and drainer), and what the user did.
final class ModelPhone: @unchecked Sendable {
    let url: URL
    let server: ModelServer
    private(set) var cache: HermesCache
    private(set) var drainer: OutboxDrainer
    private var hung: Task<Void, Error>?
    private var clockTick = 0
    /// Every message the user saved, in order.
    private(set) var written: [UUID] = []
    /// Messages the user deleted.
    private(set) var deleted: Set<UUID> = []
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    init(server: ModelServer) throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("g1-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("cache.sqlite")
        self.server = server
        cache = try HermesCache(url: url)
        drainer = OutboxDrainer(
            store: cache.outbox, chatID: "c1", submitter: server, clock: { Date(timeIntervalSince1970: 1_800_000_000) })
    }

    /// The user writes a message. It is saved before anything is sent.
    @discardableResult
    func write(_ text: String) async throws -> UUID {
        clockTick += 1
        let record = OutboundRecord(
            connectionID: "x", chatID: "c1", text: text, createdAt: start.addingTimeInterval(Double(clockTick)))
        try await cache.outbox.insert(record)
        written.append(record.id)
        return record.id
    }

    /// One drain pass. Returns false when the "process" died during it; the phone must relaunch before anything else.
    func drain() async throws -> Bool {
        let done = DoneFlag()
        let task = Task {
            defer { done.set() }
            try await drainer.drain()
        }
        while !done.value {
            if await server.crashed {
                hung = task
                return false
            }
            try await Task.sleep(for: .milliseconds(1))
        }
        try await task.value
        return true
    }

    /// The app is killed and opened again: a new store on the same file, a new drainer, and recovery.
    func relaunch() async throws {
        if let hung {
            hung.cancel()
            _ = try? await hung.value
            self.hung = nil
        }
        await server.script([])
        cache = try HermesCache(url: url)
        drainer = OutboxDrainer(
            store: cache.outbox, chatID: "c1", submitter: server, clock: { Date(timeIntervalSince1970: 1_800_000_000) })
        try await drainer.recoverInterrupted()
    }

    /// The user taps Retry on the failed message, if there is one.
    func retryFailed() async throws {
        guard let failed = try await records().first(where: { $0.state.kind == .failed }) else { return }
        try await drainer.retry(failed.id)
    }

    /// The user deletes a message that is pending or failed. A message being sent cannot be deleted.
    func delete(_ id: UUID) async throws {
        guard let record = try await records().first(where: { $0.id == id }) else { return }
        do {
            try await cache.outbox.remove(id: id, ifCurrently: record.state.kind)
            deleted.insert(id)
        } catch OutboxError.unexpectedState {
            // Refused: it moved on (or is being sent). It stays.
        }
    }

    func records() async throws -> [OutboundRecord] {
        try await cache.outbox.records(inChat: "c1")
    }
}

/// The invariants, checked after every step.
enum MessageLossRules {
    static func check(_ phone: ModelPhone, afterRelaunch: Bool, step: String) async throws {
        let records = try await phone.records()
        let stored = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        for id in phone.written {
            let deliveries = await phone.server.deliveries(of: id)
            let crashes = await phone.server.lostAcks(of: id)
            if phone.deleted.contains(id) {
                #expect(stored[id] == nil, "\(step): a deleted message came back")
                #expect(deliveries <= 1 + crashes, "\(step): a deleted message was delivered \(deliveries) times")
                continue
            }
            guard let record = stored[id] else {
                Issue.record("\(step): message \(id) is gone without being deleted")
                continue
            }
            // Sent twice only when the app died after the server got it. Without that, at most once.
            #expect(
                deliveries <= 1 + crashes, "\(step): \(record.text) delivered \(deliveries) times, \(crashes) lost acks"
            )
            if record.state.isSent {
                #expect(deliveries >= 1, "\(step): \(record.text) is marked sent but the server never got it")
            }
            if afterRelaunch {
                #expect(record.state.kind != .sending, "\(step): \(record.text) is stuck sending after a relaunch")
            }
        }
        // Order: the server's first copy of each message arrives in the order the user wrote them.
        let firstDeliveries = await phone.server.received.reduce(into: [UUID]()) { seen, id in
            if !seen.contains(id) { seen.append(id) }
        }
        let writtenOrder = phone.written.filter { firstDeliveries.contains($0) }
        #expect(firstDeliveries == writtenOrder, "\(step): the server got messages out of order")
    }
}

struct MessageLossModelTests {
    // MARK: Fixed seeds

    /// Seed 1: the app dies after the server took the message, before `.sent` was written. On relaunch the message is
    /// sent again. `prompt.submit` carries no client id, so the server cannot drop the copy. The fix is a server-side
    /// idempotency key (board row g1-submit-idempotency), not a weaker test.
    @Test func aCrashAfterTheServerTookTheMessageResendsIt() async throws {
        let server = ModelServer([.crashAfterReceipt])
        let phone = try ModelPhone(server: server)
        let id = try await phone.write("hello")

        #expect(try await phone.drain() == false)
        try await phone.relaunch()
        #expect(try await phone.drain())

        let records = try await phone.records()
        #expect(records.map(\.state.kind) == [.sent], "never lost: delivered after the relaunch")
        let deliveries = await server.deliveries(of: id)
        withKnownIssue(
            "prompt.submit has no client id, so a lost acknowledgement means a duplicate (g1-submit-idempotency)"
        ) {
            #expect(deliveries == 1)
        }
    }

    /// The same crash before the request left the phone: sent exactly once after the relaunch.
    @Test func aCrashBeforeTheServerGotTheMessageSendsItOnceAfterRelaunch() async throws {
        let server = ModelServer([.crashBeforeReceipt])
        let phone = try ModelPhone(server: server)
        let id = try await phone.write("hello")

        #expect(try await phone.drain() == false)
        try await phone.relaunch()
        try await MessageLossRules.check(phone, afterRelaunch: true, step: "relaunch")
        #expect(try await phone.drain())

        #expect(await server.deliveries(of: id) == 1)
        #expect(try await phone.records().map(\.state.kind) == [.sent])
    }

    /// Seed 2: a message being sent cannot be deleted; the late acknowledgement then lands, and the row is sent once.
    @Test func deletingAMessageInFlightIsRefusedAndTheAckStillLands() async throws {
        let cache = try HermesCache()
        let record = OutboundRecord(
            connectionID: "x", chatID: "c1", text: "a", createdAt: Date(timeIntervalSince1970: 1))
        try await cache.outbox.insert(record)
        try await cache.outbox.updateState(.sending, forID: record.id)

        await #expect(throws: OutboxError.self) { try await cache.outbox.remove(id: record.id, ifCurrently: .pending) }
        await #expect(throws: OutboxError.self) { try await cache.outbox.remove(id: record.id, ifCurrently: .failed) }
        try await cache.outbox.updateState(.sent(acknowledgedAt: Date(timeIntervalSince1970: 2)), forID: record.id)

        #expect(try await cache.outbox.records(inChat: "c1").map(\.state.kind) == [.sent])
    }

    /// Seed 2b: a failed message the user deleted never comes back, even if the server's reply to an earlier attempt
    /// arrives late (the store refuses the move for an unknown id).
    @Test func aDeletedMessageDoesNotComeBackOnALateReply() async throws {
        let cache = try HermesCache()
        let record = OutboundRecord(
            connectionID: "x", chatID: "c1", text: "a", createdAt: Date(timeIntervalSince1970: 1))
        try await cache.outbox.insert(record)
        try await cache.outbox.updateState(.sending, forID: record.id)
        try await cache.outbox.updateState(.failed(reason: "refused"), forID: record.id)
        try await cache.outbox.remove(id: record.id, ifCurrently: .failed)

        await #expect(throws: OutboxError.self) {
            try await cache.outbox.updateState(.sent(acknowledgedAt: Date(timeIntervalSince1970: 2)), forID: record.id)
        }
        #expect(try await cache.outbox.records(inChat: "c1").isEmpty)
    }

    /// Seed 3: a failed message holds back the ones written after it; retrying it sends the rest in order.
    @Test func aFailedHeadHoldsTheRestAndRetryDrainsThemInOrder() async throws {
        let server = ModelServer([.acknowledge, .refuse])
        let phone = try ModelPhone(server: server)
        for text in ["a", "b", "c", "d"] { try await phone.write(text) }

        #expect(try await phone.drain())
        #expect(try await phone.records().map(\.state.kind) == [.sent, .failed, .pending, .pending])
        try await MessageLossRules.check(phone, afterRelaunch: false, step: "after refuse")

        try await phone.retryFailed()
        #expect(try await phone.records().map(\.state.kind) == [.sent, .sent, .sent, .sent])
        #expect(await server.received == phone.written)
    }

    /// Seed 4: the chat detaches while a message is in flight (the drain is cancelled). The server's reply is still
    /// recorded, nothing after it goes out, and the next attach sends the rest exactly once.
    @Test func aDetachDuringASendRecordsTheReplyAndTheNextAttachSendsTheRestOnce() async throws {
        let server = ModelServer()
        let phone = try ModelPhone(server: server)
        for text in ["a", "b", "c"] { try await phone.write(text) }

        let pass = Task { try await phone.drainer.drain() }
        pass.cancel()
        try? await pass.value
        try await MessageLossRules.check(phone, afterRelaunch: false, step: "after detach")

        try await phone.drainer.recoverInterrupted()
        try await phone.drainer.drain()
        for id in phone.written { #expect(await server.deliveries(of: id) == 1) }
        #expect(try await phone.records().map(\.state.kind) == [.sent, .sent, .sent])
    }

    /// Seed 5: a retry that arrives while a drain runs is folded into it. No message goes out twice.
    @Test func aRetryDuringADrainSendsNothingTwice() async throws {
        let server = ModelServer([.refuse])
        let phone = try ModelPhone(server: server)
        for text in ["a", "b"] { try await phone.write(text) }
        #expect(try await phone.drain())

        async let retried: Void = phone.retryFailed()
        async let drained: Void = phone.drainer.drain()
        _ = try await (retried, drained)
        try await phone.drainer.drain()

        for id in phone.written { #expect(await server.deliveries(of: id) == 1) }
        #expect(try await phone.records().map(\.state.kind) == [.sent, .sent])
    }

    // MARK: Random walk

    /// Seeded random sequences of writes, drains with every server reply, crashes, relaunches, retries and deletes.
    /// A failure names its seed and step, so the run can be replayed.
    @Test(arguments: Array(1...40))
    func randomWalkNeverLosesAMessage(seed: UInt64) async throws {
        var random = SeededRandom(seed: seed)
        let server = ModelServer()
        let phone = try ModelPhone(server: server)
        var alive = true

        for step in 0..<30 {
            let label = "seed \(seed) step \(step)"
            if !alive {
                try await phone.relaunch()
                alive = true
                try await MessageLossRules.check(phone, afterRelaunch: true, step: "\(label) relaunch")
                continue
            }
            switch random.next(upTo: 6) {
            case 0, 1:
                try await phone.write("m\(step)")
            case 2:
                let replies: [ServerReply] = (0..<3).map { _ in
                    [
                        .acknowledge, .acknowledge, .acknowledge, .deferIt, .refuse, .crashBeforeReceipt,
                        .crashAfterReceipt,
                    ][
                        random.next(upTo: 7)]
                }
                await server.script(replies)
                alive = try await phone.drain()
            case 3:
                try await phone.relaunch()
                try await MessageLossRules.check(phone, afterRelaunch: true, step: "\(label) relaunch")
                continue
            case 4:
                try await phone.retryFailed()
            default:
                let candidates = try await phone.records().filter {
                    $0.state.kind == .pending || $0.state.kind == .failed
                }
                if !candidates.isEmpty { try await phone.delete(candidates[random.next(upTo: candidates.count)].id) }
            }
            try await MessageLossRules.check(phone, afterRelaunch: false, step: label)
        }

        // Finally: relaunch and let everything go out. Every message that was not deleted ends up sent.
        if !alive { try await phone.relaunch() }
        try await phone.relaunch()
        await server.script([])
        while try await phone.records().contains(where: { $0.state.kind == .failed }) { try await phone.retryFailed() }
        _ = try await phone.drain()
        try await MessageLossRules.check(phone, afterRelaunch: true, step: "seed \(seed) end")
        let unsent = try await phone.records().filter { !$0.state.isSent }
        #expect(unsent.isEmpty, "seed \(seed): \(unsent.map(\.text)) never went out")
    }
}

/// Set once, read from another task.
final class DoneFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var isSet = false

    var value: Bool { lock.withLock { isSet } }

    func set() { lock.withLock { isSet = true } }
}

/// A small deterministic generator (SplitMix64), so a seed always replays the same walk.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 }

    mutating func next(upTo bound: Int) -> Int {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        mixed ^= mixed >> 31
        return Int(mixed % UInt64(bound))
    }
}
