import Foundation

/// Identifiers a group room sends on the wire. The server trims them and accepts
/// `^[A-Za-z0-9][A-Za-z0-9._:-]*$` up to 128 characters (WP-43 spec, section 0).
public enum RoomIdentifier {
    /// The longest identifier the server accepts.
    public static let maxLength = 128

    private static let base36 = Array("0123456789abcdefghijklmnopqrstuvwxyz")

    /// True when the text is a valid identifier as it would be sent, without trimming.
    public static func isValid(_ text: String) -> Bool {
        guard !text.isEmpty, text.count <= maxLength else { return false }
        return text.enumerated().allSatisfy { offset, character in
            isASCIIAlphanumeric(character) || (offset > 0 && "._:-".contains(character))
        }
    }

    /// A new room id, `r<base36 milliseconds>-<5 base36 characters>`, in the form Desktop uses.
    public static func newRoomID(now: Date = Date()) -> String {
        "r" + timestamp(now) + "-" + randomSuffix()
    }

    /// A new thread id, `t<base36 milliseconds>-<5 base36 characters>`.
    public static func newThreadID(now: Date = Date()) -> String {
        "t" + timestamp(now) + "-" + randomSuffix()
    }

    /// A fresh event id for one user action. Reuse it on every retry of that action.
    public static func newEventID() -> String {
        UUID().uuidString.lowercased()
    }

    /// A fresh cancel id for one Stop tap.
    public static func newCancelID() -> String {
        "stop-" + UUID().uuidString.lowercased()
    }

    private static func timestamp(_ now: Date) -> String {
        String(Int64(now.timeIntervalSince1970 * 1000), radix: 36)
    }

    private static func randomSuffix() -> String {
        String((0..<5).map { _ in base36.randomElement() ?? "0" })
    }

    private static func isASCIIAlphanumeric(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber)
    }
}
