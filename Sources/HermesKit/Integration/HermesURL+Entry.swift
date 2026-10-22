import Foundation

/// A request to open Quick Entry, read from a `simplyhermes://quick-entry` URL.
public struct QuickEntryRoute: Equatable, Sendable {
    /// Longest prefill kept, in characters.
    public static let prefillLimit = 2000

    /// Text to put in the field. Opening Quick Entry never sends it.
    public var prefill: String?

    public init(prefill: String? = nil) {
        self.prefill = prefill
    }
}

extension HermesURL {
    private static let shareHost = "share"
    private static let quickEntryHost = "quick-entry"
    private static let prefillQueryName = "text"

    /// `simplyhermes://share/<id>`: the Share extension left a message in the outbox and asks the app to send it.
    public static func share(_ id: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = shareHost
        components.path = "/" + id
        return components.url ?? URL(string: "\(scheme)://\(shareHost)")!
    }

    /// The outbox id in a share URL. `nil` for any other URL, and for an id that is not safe as a folder name.
    public static func shareID(from url: URL) -> String? {
        guard url.scheme == scheme, url.host == shareHost else { return nil }
        let parts = url.pathComponents.dropFirst()
        guard parts.count == 1, let id = parts.first, ShareOutbox.isValidID(id) else { return nil }
        return id
    }

    /// `simplyhermes://quick-entry`, with `?text=` when the field should start with some text.
    public static func quickEntry(prefill: String? = nil) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = quickEntryHost
        if let text = cleanPrefill(prefill) {
            components.queryItems = [URLQueryItem(name: prefillQueryName, value: text)]
        }
        return components.url ?? URL(string: "\(scheme)://\(quickEntryHost)")!
    }

    /// The request in a Quick Entry URL, or `nil` for any other URL.
    public static func quickEntryRoute(from url: URL) -> QuickEntryRoute? {
        guard url.scheme == scheme, url.host == quickEntryHost else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let text = items.first { $0.name == prefillQueryName }?.value
        return QuickEntryRoute(prefill: cleanPrefill(text))
    }

    private static func cleanPrefill(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(QuickEntryRoute.prefillLimit))
    }
}
