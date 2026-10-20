import Foundation

/// Strips secrets and anything that points at the user's servers from text that goes into a public bug report.
///
/// simplyHermes issues are public, so diagnostics lose tokens, passwords, keys, cookies, hostnames, IP addresses and
/// emails before they leave the phone. `knownValues` adds exact strings the app knows are private, such as saved server
/// hosts, usernames and connection names.
public struct DiagnosticsRedactor: Sendable {
    private let known: [String]

    /// Creates a redactor. Values shorter than 3 characters are ignored, so they cannot blank out ordinary words.
    public init(knownValues: [String] = []) {
        let trimmed = knownValues.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        // Longest first, so "home.example.com" goes before "home".
        known = Array(Set(trimmed.filter { $0.count >= 3 })).sorted { $0.count > $1.count }
    }

    /// Returns `text` with every secret and private value replaced by a bracketed marker.
    public func redact(_ text: String) -> String {
        var result = text
        for value in known {
            result = result.replacingOccurrences(of: value, with: "[redacted]", options: .caseInsensitive)
        }
        return Self.apply(Self.secretRules + Self.addressRules, to: result)
    }

    /// Returns `text` with the secrets removed and the hosts, addresses and emails kept. Log views use this: an
    /// operator needs the address in a line, but no line needs a token.
    public func redactSecrets(_ text: String) -> String {
        Self.apply(Self.secretRules, to: text)
    }

    private static func apply(_ rules: [Rule], to text: String) -> String {
        var result = text
        for rule in rules {
            let range = NSRange(result.startIndex..., in: result)
            result = rule.regex.stringByReplacingMatches(in: result, range: range, withTemplate: rule.template)
        }
        return result
    }

    private struct Rule: @unchecked Sendable {
        let regex: NSRegularExpression
        let template: String

        init(_ pattern: String, _ template: String) {
            // The patterns are constants; a bad one is a programming error caught by the tests.
            // swiftlint:disable:next force_try
            regex = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            self.template = template
        }
    }

    /// Keys whose value is a secret in `key=value`, `key: value` and JSON `"key": "value"` form.
    private static let secretKeys = [
        "password", "passwd", "passphrase", "token", "access_token", "refresh_token", "id_token", "secret",
        "client_secret", "api[_-]?key", "cookie", "set-cookie", "authorization", "session_?id", "ticket",
    ]

    // Order matters: whole blocks and tokens first, then key=value pairs, then addresses.
    /// The rules that remove secrets: private key blocks, tokens, and key=value pairs.
    private static let secretRules: [Rule] = [
        Rule(#"-----BEGIN [A-Z0-9 ]+-----[\s\S]*?-----END [A-Z0-9 ]+-----"#, "[redacted key]"),
        Rule(#"\b(?:gh[pousr]_[A-Za-z0-9]{16,}|github_pat_[A-Za-z0-9_]{16,})"#, "[redacted token]"),
        Rule(#"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+"#, "[redacted token]"),
        Rule(#"\b(bearer|basic)\s+[A-Za-z0-9._~+/=-]{6,}"#, "$1 [redacted]"),
        Rule(
            #"\b("# + secretKeys.joined(separator: "|") + #")(\s*["']?\s*[:=]\s*["']?)[^\s"'&,;}]+"#, "$1$2[redacted]"),
    ]

    /// The rules that remove hosts, addresses and emails. Bug reports remove them; log views do not.
    private static let addressRules: [Rule] = [
        // A URL keeps its scheme, port and path; user info and host go.
        Rule(#"([a-z][a-z0-9+.-]*://)(?:[^/\s@]*@)?(?:\[[0-9a-f:.]+\]|[^/\s:?#]+)"#, "$1[host]"),
        Rule(#"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"#, "[redacted email]"),
        Rule(#"\b(?:\d{1,3}\.){3}\d{1,3}\b"#, "[ip]"),
        Rule(#"\b(?:[0-9a-f]{1,4}:){3,7}[0-9a-f]{1,4}\b"#, "[ip]"),
        Rule(#"\b(?:[a-z0-9-]+\.)+(?:ts\.net|local|lan|home|internal|localdomain)\b"#, "[host]"),
    ]
}
