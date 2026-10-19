/// The fields the Edit sheet can change, seeded from a bot's roster row.
/// Saving writes only the fields that differ from the row.
public struct BotEdit: Sendable, Equatable {
    public var title: String
    public var role: String
    public var avatar: BotAvatar?
    public var isPinned: Bool
    public var isHidden: Bool

    public init(entry: BotRosterEntry) {
        title = entry.title
        role = entry.role ?? ""
        avatar = entry.avatar
        isPinned = entry.isPinned
        isHidden = entry.isHidden
    }
}
