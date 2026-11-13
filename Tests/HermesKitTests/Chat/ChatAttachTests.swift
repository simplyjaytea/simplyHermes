import Foundation
import Testing

@testable import HermesKit

/// Holds each step of a fake attach at its await until the test lets it go, so a test can switch servers at exactly the
/// point where a real attach is waiting for the client, the profile or the session.
@MainActor
private final class StepGate {
    private var waiting: [String: CheckedContinuation<Void, Never>] = [:]
    private var released: Set<String> = []

    func hold(_ name: String) async {
        if released.contains(name) { return }
        await withCheckedContinuation { waiting[name] = $0 }
    }

    func release(_ name: String) {
        released.insert(name)
        waiting.removeValue(forKey: name)?.resume()
    }

    /// Returns once `name` is suspended at its await.
    func reached(_ name: String) async {
        while waiting[name] == nil { await Task.yield() }
    }
}

/// The world a chat attach runs in: the server the chat belongs to, the one that is active, and what the attach did.
@MainActor
private final class AttachWorld {
    static let stepNames = ["client", "broker", "profile", "controller", "outbox", "commit"]

    let bound = "A"
    var active = "A"
    var isRetired = false
    let gate = StepGate()
    /// Servers the attach connected to. It is taken from `bound`, never from `active`.
    private(set) var connectedTo: [String] = []
    private(set) var ran: [String] = []
    private(set) var rolledBack: [String] = []
    private(set) var committed = false
    private(set) var drained = false

    var wanted: Bool { !isRetired && active == bound }

    func steps() -> [ChatAttach.Step] {
        let server = bound  // fixed when the attach starts
        return AttachWorld.stepNames.map { name in
            if name == "commit" {
                // The commit has no await, so a switch cannot land inside it.
                return ChatAttach.Step(
                    name,
                    run: {
                        self.ran.append(name)
                        self.committed = true
                    },
                    rollback: {
                        self.committed = false
                        self.rolledBack.append(name)
                    })
            }
            return ChatAttach.Step(
                name,
                run: {
                    if name == "client" { self.connectedTo.append(server) }
                    await self.gate.hold(name)
                    self.ran.append(name)
                }, rollback: { self.rolledBack.append(name) })
        }
    }

    /// What the caller does with the outcome: drain only an attach that completed.
    func finish(_ outcome: ChatAttach.Outcome) {
        if outcome == .attached { drained = true }
    }
}

@MainActor
struct ChatAttachTests {
    private let awaiting = Array(AttachWorld.stepNames.dropLast())

    @Test func anAttachThatIsNotInterruptedRunsEveryStepAndCommits() async throws {
        let world = AttachWorld()
        let task = Task { try await ChatAttach.run(world.steps(), stillWanted: { world.wanted }) }
        for name in awaiting {
            await world.gate.reached(name)
            world.gate.release(name)
        }
        let outcome = try await task.value
        world.finish(outcome)

        #expect(outcome == .attached)
        #expect(world.ran == AttachWorld.stepNames)
        #expect(world.committed && world.drained)
        #expect(world.rolledBack.isEmpty)
        #expect(world.connectedTo == ["A"])
    }

    // Row 140, Moss's race: the switch lands while the attach waits at each await. Nothing may attach or drain.
    @Test(arguments: ["client", "broker", "profile", "controller", "outbox"])
    func aServerSwitchWhileTheAttachWaitsAbandonsItAndRollsBackWhatItDid(waitingAt: String) async throws {
        let world = AttachWorld()
        let task = Task { try await ChatAttach.run(world.steps(), stillWanted: { world.wanted }) }
        for name in awaiting {
            await world.gate.reached(name)
            if name == waitingAt {
                world.active = "B"  // the user switches servers now
                world.gate.release(name)
                break
            }
            world.gate.release(name)
        }
        for name in awaiting { world.gate.release(name) }  // a regression would run on to the end, not hang
        let outcome = try await task.value
        world.finish(outcome)

        #expect(outcome == .abandoned(step: waitingAt))
        #expect(!world.committed, "The old chat must not attach to the new server")
        #expect(!world.drained, "...and must not drain there")
        let done = Array(AttachWorld.stepNames.prefix(through: AttachWorld.stepNames.firstIndex(of: waitingAt)!))
        #expect(world.rolledBack == done.reversed(), "What the attach did is undone, last first")
        #expect(!world.ran.contains("commit"))
        #expect(world.connectedTo == ["A"], "The attach used the server it started on, not the one active at the end")
    }

    @Test(arguments: ["client", "controller", "outbox"])
    func aChatRetiredWhileTheAttachWaitsIsAbandonedToo(waitingAt: String) async throws {
        let world = AttachWorld()
        let task = Task { try await ChatAttach.run(world.steps(), stillWanted: { world.wanted }) }
        for name in awaiting {
            await world.gate.reached(name)
            if name == waitingAt {
                world.isRetired = true
                world.gate.release(name)
                break
            }
            world.gate.release(name)
        }
        for name in awaiting { world.gate.release(name) }
        #expect(try await task.value == .abandoned(step: waitingAt))
        #expect(!world.committed)
    }

    @Test func aSwitchAndSwitchBackBeforeTheCheckLeavesTheAttachWanted() async throws {
        let world = AttachWorld()
        let task = Task { try await ChatAttach.run(world.steps(), stillWanted: { world.wanted }) }
        await world.gate.reached("client")
        world.active = "B"
        world.active = "A"
        world.gate.release("client")
        for name in awaiting.dropFirst() {
            await world.gate.reached(name)
            world.gate.release(name)
        }
        #expect(try await task.value == .attached)
    }

    @Test func aCancelledAttachIsAbandonedAndRolledBack() async throws {
        let world = AttachWorld()
        let task = Task { try await ChatAttach.run(world.steps(), stillWanted: { world.wanted }) }
        await world.gate.reached("client")
        world.gate.release("client")
        await world.gate.reached("broker")
        task.cancel()
        for name in awaiting { world.gate.release(name) }
        #expect(try await task.value == .abandoned(step: "broker"))
        #expect(!world.committed)
        #expect(world.rolledBack == ["broker", "client"])
    }

    @Test func anAttachThatIsUnwantedAtTheStartRunsNothing() async throws {
        let world = AttachWorld()
        world.active = "B"
        let outcome = try await ChatAttach.run(world.steps(), stillWanted: { world.wanted })
        #expect(outcome == .abandoned(step: nil))
        #expect(world.ran.isEmpty && world.connectedTo.isEmpty && world.rolledBack.isEmpty)
    }

    @Test func aStepThatThrowsRollsBackWhatCameBeforeAndRethrows() async throws {
        struct Boom: Error, Equatable {}
        var rolledBack: [String] = []
        let steps = [
            ChatAttach.Step("one", run: {}, rollback: { rolledBack.append("one") }),
            ChatAttach.Step("two", run: { throw Boom() }, rollback: { rolledBack.append("two") }),
            ChatAttach.Step("three", run: { Issue.record("must not run") }),
        ]
        await #expect(throws: Boom()) { try await ChatAttach.run(steps, stillWanted: { true }) }
        #expect(rolledBack == ["two", "one"])
    }
}
