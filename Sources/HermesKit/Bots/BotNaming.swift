import Foundation

/// Names for bots: profile names, shown titles and `@handles`, derived the way Hermes Desktop derives them (plan 2.5, WP-42).
public enum BotNaming {
    /// Profile names the server refuses (`hermes_cli/profiles.py`).
    public static let reservedNames: Set<String> = ["hermes", "default", "test", "tmp", "root", "sudo"]

    /// The profile name a New Agent name becomes. Letters that do not fold to ASCII keep their code point as `-u<hex>-`.
    public static func slug(_ name: String) -> String {
        var raw = ""
        for character in name.precomposedStringWithCanonicalMapping {
            if character.isLetter || character.isNumber {
                // Filter scalars: a decomposed letter is one Character, so a Character test drops its base letter.
                let folded = String(
                    String(character).decomposedStringWithCompatibilityMapping.unicodeScalars
                        .filter { $0.isASCII && (Character($0).isLetter || Character($0).isNumber) }
                        .map(Character.init))
                if folded.isEmpty {
                    let scalar = character.unicodeScalars.first?.value ?? 0
                    raw += "-u" + String(scalar, radix: 16) + "-"
                } else {
                    raw += folded
                }
            } else {
                raw.append(character)
            }
        }
        return cleaned(raw.lowercased(), limit: 64)
    }

    /// True when `slug` matches `^[a-z0-9][a-z0-9_-]{0,63}$` and is not a reserved name.
    public static func isValidProfileName(_ slug: String) -> Bool {
        guard !reservedNames.contains(slug), (1...64).contains(slug.count) else { return false }
        return slug.enumerated().allSatisfy { index, character in
            let isAllowed =
                character.isASCII
                && (character.isLowercase || character.isNumber || character == "_" || character == "-")
            if index == 0 { return character.isASCII && (character.isLowercase || character.isNumber) }
            return isAllowed
        }
    }

    /// The label part of a `@name-label` handle: lowercase, non-alphanumeric runs to `-`, at most 48 characters.
    public static func labelSlug(_ label: String) -> String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var raw = ""
        for character in trimmed {
            if character.isASCII && (character.isLowercase || character.isNumber) {
                raw.append(character)
            } else {
                raw.append("-")
            }
        }
        let result = cleaned(raw, limit: 48)
        return result.isEmpty ? "connection" : result
    }

    /// The name a bot shows: its Bot Mode title, then its display name, then `Hermes` for `default`, then the
    /// profile name with `-` and `_` as spaces and each word capitalized.
    public static func displayName(profile: String, title: String?, displayName: String?) -> String {
        if let title = nonEmpty(title) { return title }
        if let displayName = nonEmpty(displayName) { return displayName }
        if profile == "default" { return "Hermes" }
        return
            profile
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .map { word in word.prefix(1).uppercased() + word.dropFirst() }
            .joined(separator: " ")
    }

    /// The handle a bot is mentioned by: `default` shows as `hermes`.
    public static func mentionHandle(_ handle: String) -> String {
        "@" + (handle == "default" ? "hermes" : handle)
    }

    /// Trims, lowercases nothing further, collapses `-` runs, trims edge `-`, and cuts at a `-` when over `limit`.
    private static func cleaned(_ raw: String, limit: Int) -> String {
        var collapsed = ""
        var previousDash = false
        for character in raw {
            let isDash = character == "-"
            let isAllowed =
                character.isASCII && (character.isLowercase || character.isNumber || character == "_" || isDash)
            let mapped: Character = isAllowed ? character : "-"
            if mapped == "-" && previousDash { continue }
            previousDash = mapped == "-"
            collapsed.append(mapped)
        }
        var trimmed = Substring(collapsed)
        while trimmed.first == "-" { trimmed = trimmed.dropFirst() }
        while trimmed.last == "-" { trimmed = trimmed.dropLast() }
        guard trimmed.count > limit else { return String(trimmed) }
        let head = trimmed.prefix(limit)
        if let dash = head.lastIndex(of: "-") {
            return String(head[..<dash])
        }
        return String(head)
    }

    static func nonEmpty(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
