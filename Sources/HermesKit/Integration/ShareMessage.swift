import Foundation

/// Builds the one message a share becomes.
public enum ShareMessage {
    /// Joins the note the user typed, the shared text and the shared links into one message.
    ///
    /// Parts are separated by a blank line. Empty parts and repeats are dropped, and a link is left out when some
    /// shared text already holds it (apps often share a link both ways). The result is cut at
    /// ``ShareLimits/maxTextCharacters``.
    public static func compose(note: String, texts: [String], urls: [URL]) -> String {
        var parts: [String] = []
        func add(_ text: String) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !parts.contains(trimmed) { parts.append(trimmed) }
        }
        add(note)
        for text in texts { add(text) }
        for url in urls {
            let link = url.absoluteString
            if !parts.contains(where: { $0.contains(link) }) { add(link) }
        }
        let message = parts.joined(separator: "\n\n")
        return message.count > ShareLimits.maxTextCharacters
            ? String(message.prefix(ShareLimits.maxTextCharacters)) : message
    }

    /// Whether a share has anything to send.
    public static func hasContent(message: String, attachmentCount: Int) -> Bool {
        attachmentCount > 0 || !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// What is being shared and the note the user added, before they choose where it goes.
public struct ShareContent: Equatable, Sendable {
    public var note: String
    public var texts: [String]
    public var urls: [URL]
    public var attachments: [SharePayload.Attachment]

    public init(note: String = "", texts: [String], urls: [URL], attachments: [SharePayload.Attachment]) {
        self.note = note
        self.texts = texts
        self.urls = urls
        self.attachments = attachments
    }

    /// The message: the note, then the text and the links (see ``ShareMessage/compose(note:texts:urls:)``).
    public var message: String {
        ShareMessage.compose(note: note, texts: texts, urls: urls)
    }

    /// Whether there is anything to send. A note alone is enough; links and files count as content.
    public var hasContent: Bool {
        ShareMessage.hasContent(message: message, attachmentCount: attachments.count)
    }

    /// The share the user confirmed, ready for ``ShareOutbox/commit(_:)``.
    public func payload(id: String, createdAt: Date, destination: SharePayload.Destination) -> SharePayload {
        SharePayload(id: id, createdAt: createdAt, destination: destination, text: message, attachments: attachments)
    }
}
