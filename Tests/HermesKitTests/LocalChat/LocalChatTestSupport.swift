import Foundation
import GRDB
import Testing

@testable import HermesKit

/// A model that returns a fixed outcome, for the local chat tests.
struct ScriptedExecutor: LocalModelExecutor {
    enum Outcome: Sendable {
        case reply(String)
        case blank
        case throwing
    }

    struct Failure: Error {}

    let availability: LocalModelAvailability
    let outcome: Outcome

    init(_ outcome: Outcome, availability: LocalModelAvailability = .available) {
        self.outcome = outcome
        self.availability = availability
    }

    func respond(instructions: String, prompt: String) async throws -> String {
        switch outcome {
        case .reply(let text): text
        case .blank: " \n\t "
        case .throwing: throw Failure()
        }
    }
}

/// A mutable slot the answerer closure reads, so a test can switch the model between two sends.
final class AnswererSlot: @unchecked Sendable {
    private let lock = NSLock()
    private var current: any LocalChatAnswerer

    init(_ current: any LocalChatAnswerer) {
        self.current = current
    }

    func set(_ answerer: any LocalChatAnswerer) {
        lock.withLock { current = answerer }
    }

    func get() -> any LocalChatAnswerer {
        lock.withLock { current }
    }
}

/// A file in the temporary directory that a test can open several times, to reopen a store as after a relaunch.
func temporaryDatabaseURL() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
        "local-chat-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder.appendingPathComponent("cache.sqlite")
}

let localChatStart = Date(timeIntervalSince1970: 1_800_000_000)

/// The table names in the database at `url`, read without the app's migrations.
func tableNames(at url: URL) throws -> [String] {
    let queue = try DatabaseQueue(path: url.path)
    return try queue.read { handle in
        try String.fetchAll(handle, sql: "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name")
    }
}
