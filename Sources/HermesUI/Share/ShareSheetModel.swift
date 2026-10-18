#if canImport(UIKit)
    import Foundation
    import HermesKit
    import Observation

    /// One line of the Share sheet's preview list.
    public struct ShareSheetItem: Identifiable, Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            case text
            case link
            case photo
            case pdf
            case file

            var systemImage: String {
                switch self {
                case .text: "text.alignleft"
                case .link: "link"
                case .photo: "photo"
                case .pdf: "doc.richtext"
                case .file: "doc"
                }
            }

            var label: String {
                switch self {
                case .text: "Text"
                case .link: "Link"
                case .photo: "Photo"
                case .pdf: "PDF"
                case .file: "File"
                }
            }
        }

        public var id: String
        public var kind: Kind
        public var title: String
        public var detail: String?
    }

    /// What the Share sheet holds: the things being shared, the places they can go, and the user's note and choice.
    ///
    /// The model never touches the network or the shared container. The Share extension stages the files, builds the
    /// model and, when the user sends, turns it into a ``SharePayload`` for the outbox.
    @MainActor
    @Observable
    public final class ShareSheetModel {
        public typealias Item = ShareSheetItem

        public let items: [Item]
        public let destinations: [ShareDestination]
        /// Calm sentences about files that were left out.
        public let notices: [String]
        /// True when the shared container is missing, so nothing can be handed to the app.
        public let isUnavailable: Bool

        public var note = ""
        public var selectedID = ShareDestination.newChat.id
        public var isSending = false

        private let texts: [String]
        private let urls: [URL]
        private let attachments: [SharePayload.Attachment]

        public init(
            texts: [String], urls: [URL], attachments: [SharePayload.Attachment], destinations: [ShareDestination],
            notices: [String] = [], isUnavailable: Bool = false
        ) {
            self.texts = texts
            self.urls = urls
            self.attachments = attachments
            self.destinations = destinations
            self.notices = notices
            self.isUnavailable = isUnavailable
            items = Self.makeItems(texts: texts, urls: urls, attachments: attachments)
        }

        public var selectedDestination: ShareDestination {
            destinations.first { $0.id == selectedID } ?? .newChat
        }

        /// What is shared plus the note typed so far.
        private var content: ShareContent {
            ShareContent(note: note, texts: texts, urls: urls, attachments: attachments)
        }

        public var canSend: Bool {
            !isUnavailable && !isSending && content.hasContent
        }

        /// The share to leave in the outbox.
        public func payload(id: String, now: Date) -> SharePayload {
            content.payload(id: id, createdAt: now, destination: selectedDestination.destination)
        }

        private static func makeItems(texts: [String], urls: [URL], attachments: [SharePayload.Attachment]) -> [Item] {
            var items: [Item] = []
            for (index, text) in texts.enumerated() {
                let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
                items.append(Item(id: "text-\(index)", kind: .text, title: cut(line, to: 80)))
            }
            for (index, url) in urls.enumerated() {
                items.append(Item(id: "link-\(index)", kind: .link, title: cut(url.absoluteString, to: 80)))
            }
            for (index, file) in attachments.enumerated() {
                let kind: Item.Kind =
                    switch file.kind {
                    case .image: .photo
                    case .pdf: .pdf
                    case .file: .file
                    }
                let size = ByteCountFormatter.string(fromByteCount: Int64(file.byteCount), countStyle: .file)
                items.append(Item(id: "file-\(index)", kind: kind, title: file.fileName, detail: size))
            }
            return items
        }

        private static func cut(_ text: String, to limit: Int) -> String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.count > limit ? String(trimmed.prefix(limit - 1)) + "…" : trimmed
        }
    }
#endif
