import Foundation
import HermesKit

/// A backend whose answers a test scripts. It counts what it was asked.
actor ScriptedJourneyBackend: JourneyBackend {
    private let graphAnswer: @Sendable (Int) async throws -> JourneyGraph
    private var detailAnswer: Result<JourneyNodeDetail, any Error>
    private var updateAnswer: Result<JourneyMutationResult, any Error>
    private var deleteAnswer: Result<JourneyMutationResult, any Error>
    private(set) var graphCalls = 0
    private(set) var updates: [String] = []
    private(set) var deletions: [String] = []

    /// `graph` gets the number of the call (1, 2, ...) and answers or throws.
    init(
        detail: Result<JourneyNodeDetail, any Error> = .success(JourneyNodeDetail(content: "Some text")),
        update: Result<JourneyMutationResult, any Error> = .success(JourneyMutationResult(ok: true)),
        delete: Result<JourneyMutationResult, any Error> = .success(JourneyMutationResult(ok: true)),
        graph: @escaping @Sendable (Int) async throws -> JourneyGraph = { _ in JourneySample.graph }
    ) {
        graphAnswer = graph
        detailAnswer = detail
        updateAnswer = update
        deleteAnswer = delete
    }

    func setDetail(_ answer: Result<JourneyNodeDetail, any Error>) { detailAnswer = answer }
    func setUpdate(_ answer: Result<JourneyMutationResult, any Error>) { updateAnswer = answer }
    func setDelete(_ answer: Result<JourneyMutationResult, any Error>) { deleteAnswer = answer }

    func learningGraph() async throws -> JourneyGraph {
        graphCalls += 1
        return try await graphAnswer(graphCalls)
    }

    func learningNode(id: String) async throws -> JourneyNodeDetail {
        try detailAnswer.get()
    }

    func updateLearningNode(id: String, content: String) async throws -> JourneyMutationResult {
        updates.append("\(id)=\(content)")
        return try updateAnswer.get()
    }

    func deleteLearningNode(id: String) async throws -> JourneyMutationResult {
        deletions.append(id)
        return try deleteAnswer.get()
    }
}

/// A backend whose graph call waits until the test lets it go, to test loads that are still running.
actor GatedJourneyBackend: JourneyBackend {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private let graph: JourneyGraph

    init(graph: JourneyGraph) {
        self.graph = graph
    }

    var waitingCount: Int { waiters.count }

    func release() {
        let all = waiters
        waiters = []
        for waiter in all { waiter.resume() }
    }

    func learningGraph() async throws -> JourneyGraph {
        await withCheckedContinuation { waiters.append($0) }
        return graph
    }

    func learningNode(id: String) async throws -> JourneyNodeDetail {
        throw RESTError.http(status: 404, detail: nil)
    }

    func updateLearningNode(id: String, content: String) async throws -> JourneyMutationResult {
        throw RESTError.http(status: 404, detail: nil)
    }

    func deleteLearningNode(id: String) async throws -> JourneyMutationResult {
        throw RESTError.http(status: 404, detail: nil)
    }
}

/// The profile a fake connection works as, changed by a test.
actor ProfileBox {
    private(set) var value: String?

    init(_ value: String?) {
        self.value = value
    }

    func set(_ value: String?) { self.value = value }
}

/// Counts calls from a `@Sendable` closure.
final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var total = 0

    /// Adds one and returns the new total.
    @discardableResult
    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        total += 1
        return total
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return total
    }
}

/// Polls until `condition` holds, for up to five seconds. Returns false on a timeout.
@MainActor
func waitUntil(_ condition: @MainActor () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(5)
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return await condition()
}

/// A `pause` for the model that returns at once.
let noPause: @Sendable (Duration) async throws -> Void = { _ in }

/// A small graph with a title that tells which profile it belongs to.
func profileGraph(_ name: String) -> JourneyGraph {
    JourneyGraph(nodes: [
        JourneyNode(id: "skill-of-\(name)", label: "Skill of \(name)", timestamp: 1_000, category: name)
    ])
}
