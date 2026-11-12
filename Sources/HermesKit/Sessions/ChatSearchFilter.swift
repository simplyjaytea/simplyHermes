import Foundation

/// The chat-list search used where the server's own search isn't available: the local chat list and the unfolded
/// sidebar. It looks at what the row shows (title, subtitle, server name), not at message text.
public enum ChatSearchFilter {
    /// True when every word of `query` appears in at least one of `fields`, ignoring case and accents. A blank query
    /// matches everything, so clearing the field shows the whole list again.
    public static func matches(_ query: String, in fields: [String]) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return words.allSatisfy { word in
            fields.contains { $0.range(of: word, options: options) != nil }
        }
    }
}
