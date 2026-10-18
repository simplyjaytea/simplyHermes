import Foundation

/// A bot avatar chosen in this app (plan Q33). With no choice stored, the avatar is the automatic monogram.
public enum BotAvatar: Sendable, Equatable {
    case emoji(String)
    case symbol(String)

    /// The stored form: `{"kind": "emoji" | "symbol", "value": String}`.
    public var json: JSONValue {
        let (kind, value): (String, String) =
            switch self {
            case .emoji(let emoji): ("emoji", emoji)
            case .symbol(let name): ("symbol", name)
            }
        return .object(["kind": .string(kind), "value": .string(value)])
    }

    public init?(json: JSONValue) {
        guard let kind = json["kind"]?.stringValue, let value = json["value"]?.stringValue, !value.isEmpty else {
            return nil
        }
        switch kind {
        case "emoji": self = .emoji(value)
        case "symbol": self = .symbol(value)
        default: return nil
        }
    }
}

/// The automatic monogram: initials from the shown name, so every bot has a face before anyone picks one.
public enum BotMonogram {
    public static func text(for displayName: String) -> String {
        let words = displayName.split(whereSeparator: { !($0.isLetter || $0.isNumber) })
        let initials: String
        switch words.count {
        case 0: return "?"
        case 1: initials = String(words[0].prefix(2))
        default: initials = String(words[0].prefix(1)) + String(words[1].prefix(1))
        }
        return initials.uppercased()
    }
}

/// A stable colour for a bot, as an index into `palette`. The same profile name always gets the same index.
public enum BotTint {
    /// Colour names the UI maps to system colours.
    public static let palette = ["blue", "teal", "indigo", "purple", "pink", "orange", "green", "gray"]

    public static func index(for profile: String) -> Int {
        // FNV-1a over the UTF-8 bytes: deterministic across launches, unlike `Hasher`.
        var hash: UInt32 = 2_166_136_261
        for byte in profile.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return Int(hash % UInt32(palette.count))
    }

    public static func name(for profile: String) -> String {
        palette[index(for: profile)]
    }
}

/// What the avatar picker offers. Fixed lists, so a choice always renders the same on every device.
public enum BotAvatarChoices {
    public static let emoji = [
        "🦉", "🐙", "🦊", "🐝", "🐢", "🦄", "🐬", "🦜", "🐼", "🐨", "🦁", "🐸",
        "🤖", "👾", "🧠", "🔭", "📚", "🧭", "🌱", "🔥", "⚡", "🌊", "🎯", "🧪",
        "🛠", "🎨", "🎵", "☕",
    ]

    public static let symbols = [
        "sparkles", "brain", "bolt", "hammer", "wrench.and.screwdriver", "terminal", "book", "magnifyingglass",
        "paintbrush", "chart.bar", "leaf", "globe", "shield", "cpu", "wand.and.stars", "music.note", "camera",
        "gamecontroller", "cart", "airplane", "pawprint", "heart", "star", "flame",
    ]
}
