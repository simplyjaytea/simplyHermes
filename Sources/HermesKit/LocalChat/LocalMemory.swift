import Foundation
import GRDB

/// One thing the local assistant knows about the user, kept on this iPhone only (local agent abilities, phase 1).
///
/// Memory belongs to local chats. It is never sent to a server and never read from one.
public struct LocalMemory: Sendable, Equatable, Identifiable {
    /// Who saved it. Phase 1 has only the user; a model save (phase 2) is shown with Undo.
    public enum Source: String, Sendable, Equatable {
        case user
        case model
    }

    public let id: UUID
    public var text: String
    public var isPinned: Bool
    public var source: Source
    public let createdAt: Date

    public init(id: UUID = UUID(), text: String, isPinned: Bool = false, source: Source = .user, createdAt: Date) {
        self.id = id
        self.text = text
        self.isPinned = isPinned
        self.source = source
        self.createdAt = createdAt
    }
}

/// Why a memory could not be saved.
public enum LocalMemoryError: Error, Sendable, Equatable {
    /// Blank after trimming.
    case empty
    /// Longer than ``LocalMemoryRules/itemLimit``.
    case tooLong
    /// The memory does not exist (deleted, or never saved).
    case notFound
}

/// The pure rules: what a memory may hold and which memories go into the model's instructions.
public enum LocalMemoryRules {
    /// Characters one memory may hold.
    public static let itemLimit = 500
    /// Characters of memory that go into the instructions. The on-device models have a small context window.
    public static let promptBudget = 1500

    /// The text as it will be saved: trimmed, with inner runs of blank lines kept as written.
    public static func validated(_ text: String) throws(LocalMemoryError) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .empty }
        guard trimmed.count <= itemLimit else { throw .tooLong }
        return trimmed
    }

    /// The memories that fit in `budget`: pinned first, then newest first. A memory that does not fit is skipped, and
    /// a shorter later one may still fit. Returned in that order.
    public static func selection(_ memories: [LocalMemory], budget: Int = promptBudget) -> [LocalMemory] {
        let ordered = memories.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        var used = 0
        var chosen: [LocalMemory] = []
        for memory in ordered {
            let cost = memory.text.count + 3  // "- " and the newline
            guard used + cost <= budget else { continue }
            used += cost
            chosen.append(memory)
        }
        return chosen
    }

    /// The instructions block for the chosen memories, or "" when there are none.
    public static func instructionsBlock(_ memories: [LocalMemory], budget: Int = promptBudget) -> String {
        let chosen = selection(memories, budget: budget)
        guard !chosen.isEmpty else { return "" }
        return "What you know about the user (saved on this iPhone):\n"
            + chosen.map { "- \($0.text)" }.joined(separator: "\n")
    }
}

/// Where local memory is kept. ``HermesCache/localMemory`` is the app's implementation; tests may use another.
public protocol LocalMemoryStore: Sendable {
    /// Every memory, pinned first, then newest first.
    func memories() async throws -> [LocalMemory]
    /// Saves a new memory. Throws ``LocalMemoryError`` for blank or too-long text.
    @discardableResult
    func save(_ text: String, source: LocalMemory.Source, at date: Date) async throws -> LocalMemory
    /// Changes a memory's text. Throws ``LocalMemoryError``.
    func update(_ id: UUID, text: String) async throws
    /// Pins or unpins a memory. Pinned memories go into the instructions first.
    func setPinned(_ id: UUID, _ isPinned: Bool) async throws
    /// Deletes one memory. Deleting a missing one does nothing, so Undo and a second tap are safe.
    func delete(_ id: UUID) async throws
    /// Deletes every memory and returns exactly the rows it deleted, read in the same transaction, so Undo brings
    /// back those and only those (a memory saved meanwhile is neither lost nor duplicated).
    @discardableResult
    func deleteAll() async throws -> [LocalMemory]
    /// Puts memories back exactly as they were (id, text, pin, source, time), all or none, for Undo of a delete.
    func restore(_ memories: [LocalMemory]) async throws
}

/// One change the user can take back. Every save and delete of a memory offers Undo; a memory the model saves on
/// its own (phase 2) shows the same Undo in the chat.
public enum LocalMemoryChange: Sendable, Equatable {
    case saved(LocalMemory)
    case deleted(LocalMemory)
    case deletedAll([LocalMemory])

    /// Takes the change back: a save is deleted, a delete is restored as it was.
    public func undo(in store: any LocalMemoryStore) async throws {
        switch self {
        case .saved(let memory):
            try await store.delete(memory.id)
        case .deleted(let memory):
            try await store.restore([memory])
        case .deletedAll(let memories):
            try await store.restore(memories)
        }
    }

    /// The Undo toast's text.
    public var summary: String {
        switch self {
        case .saved: "Saved to memory"
        case .deleted: "Memory deleted"
        case .deletedAll(let memories): memories.count == 1 ? "1 memory deleted" : "\(memories.count) memories deleted"
        }
    }
}

/// Keeps local memory in the cache database's `local_memory` table (migration `local-memory-v1`). The table lives
/// in the app's own container; nothing here reads or writes server rows.
public struct GRDBLocalMemoryStore: LocalMemoryStore {
    private let database: any DatabaseWriter

    init(database: any DatabaseWriter) {
        self.database = database
    }

    public func memories() async throws -> [LocalMemory] {
        try await database.read { handle in
            try Row.fetchAll(
                handle, sql: "SELECT * FROM local_memory ORDER BY pinned DESC, created_at DESC, memory_id"
            ).compactMap(Self.memory)
        }
    }

    @discardableResult
    public func save(_ text: String, source: LocalMemory.Source, at date: Date) async throws -> LocalMemory {
        let memory = LocalMemory(text: try LocalMemoryRules.validated(text), source: source, createdAt: date)
        try await database.write { handle in
            try handle.execute(
                sql: """
                    INSERT INTO local_memory (memory_id, text, pinned, source, created_at) VALUES (?, ?, 0, ?, ?)
                    """,
                arguments: [memory.id.uuidString, memory.text, source.rawValue, date.timeIntervalSince1970])
        }
        return memory
    }

    public func update(_ id: UUID, text: String) async throws {
        let clean = try LocalMemoryRules.validated(text)
        try await change(id, sql: "UPDATE local_memory SET text = ? WHERE memory_id = ?", [clean, id.uuidString])
    }

    public func setPinned(_ id: UUID, _ isPinned: Bool) async throws {
        try await change(
            id, sql: "UPDATE local_memory SET pinned = ? WHERE memory_id = ?", [isPinned ? 1 : 0, id.uuidString])
    }

    public func delete(_ id: UUID) async throws {
        try await database.write { handle in
            try handle.execute(sql: "DELETE FROM local_memory WHERE memory_id = ?", arguments: [id.uuidString])
        }
    }

    public func restore(_ memories: [LocalMemory]) async throws {
        // One write is one transaction: a failure part-way restores nothing.
        try await database.write { handle in
            for memory in memories {
                try handle.execute(
                    sql: """
                        INSERT OR REPLACE INTO local_memory (memory_id, text, pinned, source, created_at)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        memory.id.uuidString, memory.text, memory.isPinned ? 1 : 0, memory.source.rawValue,
                        memory.createdAt.timeIntervalSince1970,
                    ])
            }
        }
    }

    @discardableResult
    public func deleteAll() async throws -> [LocalMemory] {
        try await database.write { handle in
            let rows = try Row.fetchAll(
                handle, sql: "SELECT * FROM local_memory ORDER BY pinned DESC, created_at DESC, memory_id"
            ).compactMap(Self.memory)
            try handle.execute(sql: "DELETE FROM local_memory")
            return rows
        }
    }

    private func change(_ id: UUID, sql: String, _ arguments: StatementArguments) async throws {
        let changed = try await database.write { handle in
            try handle.execute(sql: sql, arguments: arguments)
            return handle.changesCount
        }
        if changed == 0 { throw LocalMemoryError.notFound }
    }

    private static func memory(_ row: Row) -> LocalMemory? {
        guard let id = UUID(uuidString: row["memory_id"]),
            let source = LocalMemory.Source(rawValue: row["source"])
        else { return nil }
        return LocalMemory(
            id: id, text: row["text"], isPinned: row["pinned"] as Bool, source: source,
            createdAt: Date(timeIntervalSince1970: row["created_at"]))
    }
}
