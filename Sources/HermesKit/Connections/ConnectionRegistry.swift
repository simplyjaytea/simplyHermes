import Foundation

/// Why a connection name cannot be saved (WP-15).
public enum ConnectionNameProblem: Error, Sendable, Equatable {
    /// The name is empty or only spaces.
    case empty
    /// Longer than ``SavedConnections/maxNameLength`` characters.
    case tooLong
    /// Another connection has the same name, ignoring case.
    case taken(name: String)

    /// One sentence for the form.
    public var message: String {
        switch self {
        case .empty: "Enter a name."
        case .tooLong: "Use \(SavedConnections.maxNameLength) characters or fewer."
        case .taken(let other): "“\(other)” already uses this name. Choose another."
        }
    }
}

extension SavedConnections {
    /// The longest name a connection can have.
    public static let maxNameLength = 64

    /// The primary connection.
    public var primary: ServerConnection? {
        connections.first { $0.id == primaryID } ?? connections.first
    }

    /// The connection to open after a restart: the last used one when ``openOnLaunch`` asks for it and it still
    /// exists, else the primary one.
    public var launchConnection: ServerConnection? {
        if openOnLaunch == .lastUsed, let last = connections.first(where: { $0.id == lastUsedID }) { return last }
        return primary
    }

    /// Makes a connection the primary one.
    public mutating func setPrimary(_ id: UUID) {
        guard connections.contains(where: { $0.id == id }) else { return }
        primaryID = id
    }

    /// Records a successful connect, for ``OpenOnLaunch/lastUsed``.
    public mutating func markConnected(_ id: UUID) {
        guard connections.contains(where: { $0.id == id }) else { return }
        lastUsedID = id
    }

    /// Checks a name for the connection `id`: not empty, at most 64 characters, unique ignoring case.
    /// The name is compared trimmed.
    public func nameProblem(_ name: String, for id: UUID) -> ConnectionNameProblem? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty }
        if trimmed.count > Self.maxNameLength { return .tooLong }
        let other = connections.first {
            $0.id != id
                && $0.name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(trimmed)
                    == .orderedSame
        }
        return other.map { .taken(name: $0.name) }
    }

    /// `base`, or `base 2`, `base 3`… when the name is taken. For names the app makes up, such as a host name.
    public func uniqueName(_ base: String, for id: UUID) -> String {
        let trimmed = String(base.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxNameLength - 4))
        guard nameProblem(trimmed, for: id) != nil else { return trimmed }
        var number = 2
        while nameProblem("\(trimmed) \(number)", for: id) != nil { number += 1 }
        return "\(trimmed) \(number)"
    }
}
