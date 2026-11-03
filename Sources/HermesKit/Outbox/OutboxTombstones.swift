import Foundation

/// Chats the server has deleted whose outbox messages are not purged yet. A tombstone is written right after the
/// server delete succeeds and removed once the purge succeeds, so a purge that fails, or a crash in between, is finished
/// by ``sweep(store:)`` at the next launch.
///
/// Only chats the user deleted are swept. Sweeping every chat missing from the server's list would be unsafe: that
/// list leaves out archived, hidden and older chats and any chat created after the last refresh, and their waiting
/// messages must never be dropped.
public struct OutboxTombstones: @unchecked Sendable {
    public struct Entry: Hashable, Sendable {
        public let connection: String
        public let chatID: String

        public init(connection: String, chatID: String) {
            self.connection = connection
            self.chatID = chatID
        }
    }

    static let key = "outbox.tombstones"
    private static let separator: Character = "\u{1F}"

    /// The app's tombstones, in the standard defaults.
    public static let standard = OutboxTombstones(defaults: .standard)

    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public var entries: Set<Entry> {
        lock.withLock { load() }
    }

    public func add(_ entry: Entry) {
        lock.withLock {
            var all = load()
            all.insert(entry)
            save(all)
        }
    }

    public func remove(_ entry: Entry) {
        lock.withLock {
            var all = load()
            all.remove(entry)
            save(all)
        }
    }

    /// Purges the messages of every tombstoned chat and drops each tombstone whose purge worked. Returns how many chats
    /// were cleaned up. A purge that throws keeps its tombstone for the next sweep.
    @discardableResult
    public func sweep(store: any OutboxStore) async -> Int {
        var cleaned = 0
        for entry in entries {
            do {
                try await store.removeChat(entry.chatID, connection: entry.connection)
                remove(entry)
                cleaned += 1
            } catch {
                continue
            }
        }
        return cleaned
    }

    private func load() -> Set<Entry> {
        let raw = defaults.stringArray(forKey: Self.key) ?? []
        return Set(
            raw.compactMap { line in
                let parts = line.split(separator: Self.separator, maxSplits: 1, omittingEmptySubsequences: false)
                return parts.count == 2 ? Entry(connection: String(parts[0]), chatID: String(parts[1])) : nil
            })
    }

    private func save(_ all: Set<Entry>) {
        defaults.set(all.map { "\($0.connection)\(Self.separator)\($0.chatID)" }.sorted(), forKey: Self.key)
    }
}
