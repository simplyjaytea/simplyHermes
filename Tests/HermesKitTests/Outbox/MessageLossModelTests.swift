import Foundation
import Testing

@testable import HermesKit

// G1: the message-loss model test (Shared/simplyhermes-gilfoyle-proposals-2026-11-02.md). Fixed seeds for the
// orderings that broke before, then seeded random walks that are replayed and shrunk to the shortest failing sequence.
// The rule under test: from the moment a message is saved, it is delivered, waiting, visibly failed, or deleted or
// edited by the user. Never gone, never stuck sending after a relaunch, never overtaken, and sent to the server again
// only when the app died after the server got it (prompt.submit has no client id: row g1-submit-idempotency).

/// What the model server does with the next delivery.
enum ServerReply: String, Sendable, Equatable, CaseIterable {
    case acknowledge
    /// Busy or not live: the message stays pending.
    case deferIt
    /// The server refuses the prompt.
    case refuse
    /// The app dies before the request leaves the phone. The server never sees it.
    case crashBeforeReceipt
    /// The app dies after the server took the message, before the acknowledgement was recorded.
    case crashAfterReceipt
    /// The delivery waits until the test releases it with another reply. Fixed seeds use it to overlap actions.
    case gate
}

typealias Record = OutboundRecord

/// Raised by a dead process's store: a killed app writes nothing.
struct ProcessIsDead: Error {}

/// One app process's view of the outbox. After the process is killed, every call throws, so nothing the dead process
/// was doing can reach the file.
final class ProcessStore: OutboxStore, @unchecked Sendable {
    private let base: GRDBOutboxStore
    private let lock = NSLock()
    private var dead = false

    init(_ base: GRDBOutboxStore) { self.base = base }

    func kill() { lock.withLock { dead = true } }

    private func alive() throws {
        if lock.withLock({ dead }) { throw ProcessIsDead() }
    }

    func insert(_ record: OutboundRecord) async throws {
        try alive()
        try await base.insert(record)
    }

    func updateState(_ state: DeliveryState, forID id: UUID) async throws -> OutboundRecord {
        try alive()
        return try await base.updateState(state, forID: id)
    }

    func updateState(_ state: DeliveryState, forID id: UUID, ifCurrently kind: DeliveryKind) async throws -> Record {
        try alive()
        return try await base.updateState(state, forID: id, ifCurrently: kind)
    }

    func records(inChat chatID: String) async throws -> [OutboundRecord] {
        try alive()
        return try await base.records(inChat: chatID)
    }

    func pruneSent(inChat chatID: String) async throws -> Int {
        try alive()
        return try await base.pruneSent(inChat: chatID)
    }

    func remove(id: UUID, ifCurrently current: DeliveryKind) async throws {
        try alive()
        try await base.remove(id: id, ifCurrently: current)
    }

    func removeChat(_ chatID: String, connection: String) async throws -> Int {
        try alive()
        return try await base.removeChat(chatID, connection: connection)
    }
}

/// The server side of the model. It records every delivery it receives and counts the replies it gave.
actor ModelServer: OutboxSubmitter {
    private var replies: [ServerReply] = []
    private(set) var received: [UUID] = []
    private(set) var crashed = false
    private(set) var lostAcks: [UUID: Int] = [:]
    private(set) var used: [ServerReply: Int] = [:]
    private(set) var inFlight: UUID?
    private var gateRelease: CheckedContinuation<ServerReply, Never>?

    init(_ replies: [ServerReply] = []) { self.replies = replies }

    func script(_ next: [ServerReply]) {
        replies = next
        crashed = false
    }

    func deliver(_ record: OutboundRecord) async -> SubmitOutcome {
        var reply = replies.isEmpty ? .acknowledge : replies.removeFirst()
        if reply == .gate {
            inFlight = record.id
            reply = await withCheckedContinuation { gateRelease = $0 }
            inFlight = nil
        }
        used[reply, default: 0] += 1
        switch reply {
        case .acknowledge, .gate:
            received.append(record.id)
            return .acknowledged
        case .deferIt:
            return .deferred
        case .refuse:
            return .failed("refused")
        case .crashBeforeReceipt:
            crashed = true
            return await hang()
        case .crashAfterReceipt:
            received.append(record.id)
            lostAcks[record.id, default: 0] += 1
            crashed = true
            return await hang()
        }
    }

    /// Releases a delivery held at a `.gate` with `reply`.
    func release(_ reply: ServerReply) {
        gateRelease?.resume(returning: reply)
        gateRelease = nil
    }

    /// The killed process never gets an answer. When its task is cancelled the call returns, but the process store
    /// is dead by then, so nothing it does next is written.
    private func hang() async -> SubmitOutcome {
        while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(1)) }
        return .deferred
    }

    func deliveries(of id: UUID) -> Int { received.filter { $0 == id }.count }
}

/// One phone: the cache file, the current process (its store and drainer), and what the user did.
final class ModelPhone: @unchecked Sendable {
    let url: URL
    let server: ModelServer
    private(set) var process: ProcessStore
    /// Reads the file directly, for the invariants: what is on disk, whatever the current process is doing.
    let disk: GRDBOutboxStore
    private(set) var drainer: OutboxDrainer
    private var hung: Task<Void, Error>?
    private var tick = 0
    private(set) var isDead = false
    /// Every message the user saved, in writing order.
    private(set) var written: [(id: UUID, text: String)] = []
    /// Messages the user deleted, or replaced by editing them.
    private(set) var removed: Set<UUID> = []
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    init(server: ModelServer) throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("g1-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("cache.sqlite")
        self.server = server
        disk = try HermesCache(url: url).outbox
        process = ProcessStore(try HermesCache(url: url).outbox)
        drainer = OutboxDrainer(store: process, chatID: "c1", submitter: server)
    }

    /// The user writes a message. It is saved before anything is sent.
    @discardableResult
    func write(_ text: String) async throws -> UUID {
        tick += 1
        let record = OutboundRecord(
            connectionID: "x", chatID: "c1", text: text, createdAt: start.addingTimeInterval(Double(tick)))
        try await process.insert(record)
        written.append((record.id, text))
        return record.id
    }

    /// One drain pass. Returns false when the process died during it. The process is then dead until `relaunch()`.
    func drain() async throws -> Bool {
        try await runProcess { try await self.drainer.drain() }
    }

    /// Runs one piece of the app's work, watching for a crash reply from the server. On a crash the process is killed
    /// at once (its store refuses every write), its work is left hanging, and this returns false.
    private func runProcess(_ work: @escaping @Sendable () async throws -> Void) async throws -> Bool {
        let done = DoneFlag()
        let task = Task {
            defer { done.set() }
            try await work()
        }
        while !done.value {
            if await server.crashed {
                process.kill()
                isDead = true
                hung = task
                return false
            }
            try await Task.sleep(for: .milliseconds(1))
        }
        try await task.value
        return true
    }

    /// The app is killed and opened again: a new process store on the same file, a new drainer, and recovery.
    func relaunch() async throws {
        process.kill()
        if let hung {
            hung.cancel()
            _ = try? await hung.value
            self.hung = nil
        }
        await server.script([])
        process = ProcessStore(try HermesCache(url: url).outbox)
        drainer = OutboxDrainer(store: process, chatID: "c1", submitter: server)
        try await drainer.recoverInterrupted()
        isDead = false
    }

    /// The user taps Retry on the failed message, if there is one. Retry drains, so it can crash too. Returns false
    /// when the process died.
    @discardableResult
    func retryFailed() async throws -> Bool {
        guard let failed = try await records().first(where: { $0.state.kind == .failed }) else { return true }
        return try await runProcess { try await self.drainer.retry(failed.id) }
    }

    /// The user deletes a message. Only a pending or failed message can go; one being sent stays.
    func delete(_ id: UUID) async throws {
        // The screen offers Delete only on a waiting or failed message, and the store checks that state in the same
        // write as the delete.
        guard let record = try await records().first(where: { $0.id == id }),
            record.state.kind == .pending || record.state.kind == .failed
        else { return }
        do {
            try await process.remove(id: id, ifCurrently: record.state.kind)
            removed.insert(id)
        } catch OutboxError.unexpectedState {
        } catch OutboxError.notFound {}
    }

    /// The user edits a message: the old one is removed and the new text is saved as a new message. A message being
    /// sent cannot be edited, so the edit is refused and the original stays.
    func edit(_ id: UUID, to text: String) async throws {
        guard let record = try await records().first(where: { $0.id == id }), record.state.kind != .sending else {
            return
        }
        do {
            try await process.remove(id: id, ifCurrently: record.state.kind)
        } catch OutboxError.unexpectedState {
            return
        }
        removed.insert(id)
        try await write(text)
    }

    func records() async throws -> [OutboundRecord] {
        try await process.records(inChat: "c1")
    }
}

/// The invariants. Each returns what is wrong, so a walk can be replayed and shrunk.
enum MessageLossRules {
    static func violations(_ phone: ModelPhone, afterRelaunch: Bool) async throws -> [String] {
        var problems: [String] = []
        let stored = Dictionary(uniqueKeysWithValues: try await phone.disk.records(inChat: "c1").map { ($0.id, $0) })
        let received = await phone.server.received
        for (id, text) in phone.written {
            let deliveries = received.filter { $0 == id }.count
            let lost = await phone.server.lostAcks[id] ?? 0
            if deliveries > 1 + lost { problems.append("\(text) delivered \(deliveries) times with \(lost) lost acks") }
            if phone.removed.contains(id) {
                if stored[id] != nil { problems.append("\(text) was deleted but came back") }
                continue
            }
            guard let record = stored[id] else {
                problems.append("\(text) is gone without being deleted")
                continue
            }
            if record.state.isSent, deliveries == 0 {
                problems.append("\(text) is marked sent but was never delivered")
            }
            if afterRelaunch, record.state.kind == .sending {
                problems.append("\(text) is stuck sending after relaunch")
            }
        }
        // Order: among messages the user kept, the delivered ones are a prefix of the writing order, and the server's
        // first copies arrive in that order. An overtaken message is caught as soon as a later one is delivered.
        let delivered = Set(received)
        let kept = phone.written.filter { !phone.removed.contains($0.id) }
        let gap = kept.firstIndex { !delivered.contains($0.id) } ?? kept.endIndex
        if let overtaker = kept[gap...].first(where: { delivered.contains($0.id) }) {
            problems.append("\(overtaker.text) was delivered before \(kept[gap].text)")
        }
        let firstCopies = received.reduce(into: [UUID]()) { seen, id in if !seen.contains(id) { seen.append(id) } }
        let writtenOrder = phone.written.map(\.id).filter { firstCopies.contains($0) }
        if firstCopies != writtenOrder { problems.append("the server got messages out of writing order") }
        return problems
    }
}

/// One step of a random walk. Picks are resolved against the records present when the step runs.
enum WalkOp: Sendable, CustomStringConvertible {
    case write
    case drain([ServerReply])
    case relaunch
    case retry
    case delete(pick: Int)
    case edit(pick: Int)

    var description: String {
        switch self {
        case .write: "write"
        case .drain(let replies): "drain(\(replies.map(\.rawValue).joined(separator: ",")))"
        case .relaunch: "relaunch"
        case .retry: "retry"
        case .delete(let pick): "delete(#\(pick))"
        case .edit(let pick): "edit(#\(pick))"
        }
    }
}

/// Runs walks and shrinks failing ones.
enum Walk {
    static let walkReplies: [ServerReply] = [
        .acknowledge, .acknowledge, .deferIt, .refuse, .crashBeforeReceipt, .crashAfterReceipt,
    ]

    static func ops(seed: UInt64, steps: Int) -> [WalkOp] {
        var random = SeededRandom(seed: seed)
        return (0..<steps).map { _ in
            switch random.next(upTo: 7) {
            case 0, 1: .write
            case 2, 3: .drain((0..<3).map { _ in walkReplies[random.next(upTo: walkReplies.count)] })
            case 4: [.relaunch, .retry][random.next(upTo: 2)]
            case 5: .delete(pick: random.next(upTo: 8))
            default: .edit(pick: random.next(upTo: 8))
            }
        }
    }

    /// Runs `ops`, then lets everything go out. Returns the first problem as "step: problem", or nil. `used` collects
    /// the server replies the walk produced.
    static func run(_ ops: [WalkOp], used: inout [ServerReply: Int]) async throws -> String? {
        let server = ModelServer()
        let phone = try ModelPhone(server: server)
        defer { try? FileManager.default.removeItem(at: phone.url.deletingLastPathComponent()) }
        for (step, action) in ops.enumerated() {
            // A process that died in the last step is relaunched first, and recovery is checked right away, before this
            // step can crash it again.
            if phone.isDead {
                try await phone.relaunch()
                if let problem = try await MessageLossRules.violations(phone, afterRelaunch: true).first {
                    await collect(server, into: &used)
                    return "step \(step) (relaunch before \(action)): \(problem)"
                }
            }
            let editable = try await phone.records().filter { $0.state.kind == .pending || $0.state.kind == .failed }
            switch action {
            case .write: try await phone.write("m\(step)")
            case .drain(let replies):
                await server.script(replies)
                _ = try await phone.drain()
            case .relaunch: try await phone.relaunch()
            case .retry: _ = try await phone.retryFailed()
            case .delete(let pick):
                if !editable.isEmpty { try await phone.delete(editable[pick % editable.count].id) }
            case .edit(let pick):
                if !editable.isEmpty { try await phone.edit(editable[pick % editable.count].id, to: "e\(step)") }
            }
            let justRelaunched: Bool
            if case .relaunch = action { justRelaunched = true } else { justRelaunched = false }
            if let problem = try await MessageLossRules.violations(phone, afterRelaunch: justRelaunched).first {
                await collect(server, into: &used)
                return "step \(step) (\(action)): \(problem)"
            }
        }
        // Finish: relaunch, retry every failed message, and drain. Whatever the user kept ends up sent.
        try await phone.relaunch()
        await server.script([])
        for _ in 0..<phone.written.count {
            guard try await phone.records().contains(where: { !$0.state.isSent }) else { break }
            _ = try await phone.retryFailed()
            _ = try await phone.drain()
        }
        await collect(server, into: &used)
        if let problem = try await MessageLossRules.violations(phone, afterRelaunch: true).first {
            return "end: \(problem)"
        }
        let unsent = try await phone.records().filter { !$0.state.isSent }.map(\.text)
        return unsent.isEmpty ? nil : "end: \(unsent) never went out"
    }

    private static func collect(_ server: ModelServer, into used: inout [ServerReply: Int]) async {
        for (reply, count) in await server.used { used[reply, default: 0] += count }
    }

    /// The shortest failing sequence found: the shortest failing prefix, then each op dropped if it still fails.
    static func shrink(_ ops: [WalkOp]) async throws -> (ops: [WalkOp], problem: String) {
        var ignored: [ServerReply: Int] = [:]
        var best = ops
        var problem = try await run(ops, used: &ignored) ?? "?"
        for length in 1..<max(ops.count, 1) {
            if let found = try await run(Array(ops.prefix(length)), used: &ignored) {
                best = Array(ops.prefix(length))
                problem = found
                break
            }
        }
        var index = 0
        while index < best.count {
            var candidate = best
            candidate.remove(at: index)
            if let found = try await run(candidate, used: &ignored) {
                best = candidate
                problem = found
            } else {
                index += 1
            }
        }
        return (best, problem)
    }
}

struct MessageLossModelTests {
    // MARK: Fixed seeds

    /// Seed 1: the app dies after the server took the message, before `.sent` was written. On relaunch the message is
    /// sent again. `prompt.submit` carries no client id, so the server cannot drop the copy (g1-submit-idempotency).
    @Test func aCrashAfterTheServerTookTheMessageResendsIt() async throws {
        let server = ModelServer([.crashAfterReceipt])
        let phone = try ModelPhone(server: server)
        let id = try await phone.write("hello")

        #expect(try await phone.drain() == false)
        try await phone.relaunch()
        #expect(try await MessageLossRules.violations(phone, afterRelaunch: true).isEmpty)
        #expect(try await phone.drain())

        #expect(try await phone.records().map(\.state.kind) == [.sent], "never lost: delivered after the relaunch")
        let deliveries = await server.deliveries(of: id)
        withKnownIssue(
            "prompt.submit has no client id, so a lost acknowledgement means a duplicate (g1-submit-idempotency)"
        ) {
            #expect(deliveries == 1)
        }
    }

    /// The same crash before the request left the phone: the dead process writes nothing, recovery puts the message
    /// back to pending, and it goes out exactly once.
    @Test func aCrashBeforeTheServerGotTheMessageSendsItOnceAfterRelaunch() async throws {
        let server = ModelServer([.crashBeforeReceipt])
        let phone = try ModelPhone(server: server)
        let id = try await phone.write("hello")

        #expect(try await phone.drain() == false)
        try await phone.relaunch()
        #expect(try await phone.records().map(\.state.kind) == [.pending], "recovery must undo the interrupted send")
        #expect(try await MessageLossRules.violations(phone, afterRelaunch: true).isEmpty)
        #expect(try await phone.drain())

        #expect(await server.deliveries(of: id) == 1)
        #expect(try await phone.records().map(\.state.kind) == [.sent])
    }

    /// Seed 2: a message being sent cannot be deleted or edited. The late acknowledgement lands, and the original is
    /// sent once.
    @Test func deletingOrEditingAMessageInFlightIsRefusedAndTheAckStillLands() async throws {
        let server = ModelServer([.gate])
        let phone = try ModelPhone(server: server)
        let id = try await phone.write("original")

        let pass = Task { try await phone.drain() }
        while await server.inFlight == nil { try await Task.sleep(for: .milliseconds(1)) }
        try await phone.delete(id)
        try await phone.edit(id, to: "edited")
        await server.release(.acknowledge)
        _ = try await pass.value

        #expect(phone.removed.isEmpty)
        #expect(try await phone.records().map(\.text) == ["original"])
        #expect(try await phone.records().map(\.state.kind) == [.sent])
        #expect(await server.deliveries(of: id) == 1)
        #expect(try await MessageLossRules.violations(phone, afterRelaunch: false).isEmpty)
    }

    /// Seed 2b: a failed message the user deleted never comes back, even if a reply to an earlier attempt arrives late.
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

    /// Seed 2c: editing a failed message replaces it. The edit goes out once and the original never does.
    @Test func editingAFailedMessageSendsOnlyTheEdit() async throws {
        let server = ModelServer([.refuse])
        let phone = try ModelPhone(server: server)
        let original = try await phone.write("original")
        #expect(try await phone.drain())

        try await phone.edit(original, to: "edited")
        #expect(try await phone.drain())

        #expect(try await phone.records().map(\.text) == ["edited"])
        #expect(try await phone.records().map(\.state.kind) == [.sent])
        #expect(await server.deliveries(of: original) == 0)
        #expect(try await MessageLossRules.violations(phone, afterRelaunch: false).isEmpty)
    }

    /// Seed 3: a failed message holds back the ones written after it; retrying it sends the rest in order.
    @Test func aFailedHeadHoldsTheRestAndRetryDrainsThemInOrder() async throws {
        let server = ModelServer([.acknowledge, .refuse])
        let phone = try ModelPhone(server: server)
        for text in ["a", "b", "c", "d"] { try await phone.write(text) }

        #expect(try await phone.drain())
        #expect(try await phone.records().map(\.state.kind) == [.sent, .failed, .pending, .pending])
        #expect(try await MessageLossRules.violations(phone, afterRelaunch: false).isEmpty)

        try await phone.retryFailed()
        #expect(try await phone.records().map(\.state.kind) == [.sent, .sent, .sent, .sent])
        #expect(await server.received == phone.written.map(\.id))
    }

    /// Seed 4: the chat detaches while a message is in flight (the drain is cancelled mid-delivery). The server's reply
    /// is still recorded, nothing after it goes out, and the next attach sends the rest exactly once.
    @Test func aDetachDuringASendRecordsTheReplyAndTheNextAttachSendsTheRestOnce() async throws {
        let server = ModelServer([.gate])
        let phone = try ModelPhone(server: server)
        for text in ["a", "b", "c"] { try await phone.write(text) }

        let pass = Task { try await phone.drainer.drain() }
        while await server.inFlight == nil { try await Task.sleep(for: .milliseconds(1)) }
        pass.cancel()
        await server.release(.acknowledge)
        try? await pass.value

        #expect(try await phone.records().map(\.state.kind) == [.sent, .pending, .pending])
        #expect(await server.received == [phone.written[0].id])
        #expect(try await MessageLossRules.violations(phone, afterRelaunch: false).isEmpty)

        try await phone.drainer.recoverInterrupted()
        try await phone.drainer.drain()
        for (id, _) in phone.written { #expect(await server.deliveries(of: id) == 1) }
        #expect(try await phone.records().map(\.state.kind) == [.sent, .sent, .sent])
    }

    /// Seed 5: a retry and a drain overlap: the retried message is held at the server while a second drain is asked
    /// for. The second drain is folded in, and no message goes out twice.
    @Test func aRetryDuringADrainSendsNothingTwice() async throws {
        let server = ModelServer([.refuse])
        let phone = try ModelPhone(server: server)
        for text in ["a", "b"] { try await phone.write(text) }
        #expect(try await phone.drain())
        #expect(try await phone.records().map(\.state.kind) == [.failed, .pending])

        await server.script([.gate])
        let retry = Task { try await phone.retryFailed() }
        while await server.inFlight == nil { try await Task.sleep(for: .milliseconds(1)) }
        try await phone.drainer.drain()
        #expect(await server.received.isEmpty, "the overlapping drain must not send while the retry is in flight")
        await server.release(.acknowledge)
        try await retry.value

        for (id, _) in phone.written { #expect(await server.deliveries(of: id) == 1) }
        #expect(try await phone.records().map(\.state.kind) == [.sent, .sent])
    }

    // MARK: Random walks

    /// 40 seeded walks of 30 steps over writes, drains with every server reply, crashes, relaunches, retries, deletes
    /// and edits. A failure is shrunk to the shortest sequence that still fails, and that sequence is printed. Across
    /// all walks, every reply kind must actually happen, so a walk that never refuses cannot pass unnoticed.
    @Test func randomWalksNeverLoseAMessage() async throws {
        var used: [ServerReply: Int] = [:]
        for seed in UInt64(1)...40 {
            let ops = Walk.ops(seed: seed, steps: 30)
            if try await Walk.run(ops, used: &used) != nil {
                let shortest = try await Walk.shrink(ops)
                Issue.record(
                    "seed \(seed): \(shortest.problem). Shortest repro (\(shortest.ops.count) ops): \(shortest.ops)")
            }
        }
        for reply in Walk.walkReplies {
            #expect((used[reply] ?? 0) > 0, "the walks never produced \(reply)")
        }
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
