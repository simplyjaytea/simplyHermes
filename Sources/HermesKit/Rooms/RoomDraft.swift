import Foundation

extension RoomMember {
    /// A local bot as a room member. Its id and handle follow its profile, except `default`, which is handled as
    /// `hermes` (WP-43 spec, section 1).
    public static func local(profile: String, displayName: String? = nil) -> RoomMember {
        RoomMember(
            memberID: profile, profile: profile, handle: profile == "default" ? "hermes" : profile,
            displayName: displayName)
    }
}

/// What the New Room sheet collects: a name and two to six bots of this gateway. The checks run here, as the server runs
/// them, so the sheet can say what blocks Create (WP-43 spec, section 1).
public struct RoomDraft: Sendable, Equatable {
    /// Why a draft cannot be created.
    public enum Problem: Sendable, Equatable {
        case memberCount
        case duplicateHandle(String)
        case reservedHandle(String)
        case nameLength

        /// The words the sheet shows for this problem.
        public var message: String {
            switch self {
            case .memberCount:
                return "Pick two to six bots."
            case .duplicateHandle(let handle):
                return "Two members use @\(handle). Each bot needs its own handle."
            case .reservedHandle(let handle):
                return "@\(handle) is reserved. Pick other bots."
            case .nameLength:
                return "Give the room a name of up to \(RoomDraft.maxNameLength) characters."
            }
        }
    }

    /// Fewest members a room takes.
    public static let minMembers = 2
    /// Most members a room takes.
    public static let maxMembers = 6
    /// Longest room name the server takes.
    public static let maxNameLength = 200
    /// Handles a room reserves: `all` and `everyone` address the room, and `user` is for the person.
    public static let reservedHandles: Set<String> = ["all", "everyone", "user"]

    /// The name the user typed. Blank means the members' names are used.
    public var name: String
    /// The bots in the room.
    public var members: [RoomMember]

    /// Creates a draft.
    public init(name: String = "", members: [RoomMember] = []) {
        self.name = name
        self.members = members
    }

    /// The trimmed name, or the member names joined by ", " when the name is blank.
    public var effectiveName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty else { return trimmed }
        return members.map { member in
            member.displayName ?? (member.profile == "default" ? "Hermes" : (member.profile ?? ""))
        }.joined(separator: ", ")
    }

    /// Every reason the draft cannot be created. Empty means it can.
    public func problems() -> [Problem] {
        var found: [Problem] = []
        if !(Self.minMembers...Self.maxMembers).contains(members.count) {
            found.append(.memberCount)
        }
        var seen: Set<String> = []
        for member in members {
            let handle = member.handle ?? ""
            let keys = Set([member.memberID ?? "", handle, member.profile ?? ""].map { $0.lowercased() })
            if !keys.isDisjoint(with: seen) {
                found.append(.duplicateHandle(handle))
            }
            seen.formUnion(keys)
            if Self.reservedHandles.contains(handle.lowercased()) {
                found.append(.reservedHandle(handle))
            }
        }
        let length = effectiveName.count
        if length == 0 || length > Self.maxNameLength {
            found.append(.nameLength)
        }
        return found
    }
}
