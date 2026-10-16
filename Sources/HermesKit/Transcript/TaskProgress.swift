/// The agent's todo list reduced to what the progress pill shows.
///
/// The server sends todo items as raw JSON owned by the todo tool, so parsing is tolerant: an item is an object with
/// a text under `content`, `title`, `text` or `task`, and a `status` string. Anything else is skipped.
public struct TaskProgress: Sendable, Equatable {
    /// How far one task is.
    public enum Status: Sendable, Equatable {
        case pending
        case active
        case done
        case cancelled
    }

    /// One task in the list.
    public struct Item: Sendable, Equatable, Identifiable {
        public var id: Int
        public var text: String
        public var status: Status
    }

    /// The tasks, in the agent's order.
    public var items: [Item]

    /// Reads the raw todo list. Returns nil when it holds no readable task.
    public init?(_ raw: [JSONValue]) {
        var parsed: [Item] = []
        for (index, value) in raw.enumerated() {
            guard case .object(let fields) = value else { continue }
            let keys = ["content", "title", "text", "task"]
            let text = keys.compactMap { fields[$0]?.stringValue }.first(where: { !$0.isEmpty })
            guard let text else { continue }
            parsed.append(Item(id: index, text: text, status: Self.status(fields["status"]?.stringValue)))
        }
        guard !parsed.isEmpty else { return nil }
        items = parsed
    }

    /// Tasks that are finished or dropped.
    public var finished: Int { items.filter { $0.status == .done || $0.status == .cancelled }.count }

    /// True when every task is finished or dropped.
    public var isComplete: Bool { finished == items.count }

    /// The task being worked on, else the first one waiting.
    public var current: Item? {
        items.first(where: { $0.status == .active }) ?? items.first(where: { $0.status == .pending })
    }

    /// "2 of 5" for the collapsed pill.
    public var summary: String { "\(finished) of \(items.count)" }

    private static func status(_ raw: String?) -> Status {
        switch raw?.lowercased() {
        case "completed", "complete", "done": .done
        case "in_progress", "in-progress", "active", "running": .active
        case "cancelled", "canceled", "skipped": .cancelled
        default: .pending
        }
    }
}
