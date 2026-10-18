import Foundation

/// A file the user attached in the composer. It stays on the phone until the message goes out, then it is queued
/// as an image, rendered as pages, or staged in the session workspace.
public struct ComposerAttachment: Sendable, Equatable, Identifiable {
    /// How the file reaches the server.
    public enum Kind: Sendable, Equatable {
        /// A photo, sent with `image.attach_bytes`.
        case image
        /// A PDF, rendered to page images with `pdf.attach`.
        case pdf
        /// Any other file, staged with `file.attach` and referenced by its `@file:` text.
        case file
    }

    /// Largest file the phone sends. Bigger files are refused before upload.
    public static let maxBytes = 20 * 1024 * 1024

    public let id: UUID
    public var kind: Kind
    /// File name, shown in the composer and sent to the server.
    public var name: String
    public var data: Data

    /// Creates an attachment for a file that is already in memory.
    public init(id: UUID = UUID(), kind: Kind, name: String, data: Data) {
        self.id = id
        self.kind = kind
        self.name = name
        self.data = data
    }

    /// The MIME type, from the file extension. Unknown extensions are `application/octet-stream`.
    public var mimeType: String {
        switch URL(fileURLWithPath: name).pathExtension.lowercased() {
        case "jpg", "jpeg": "image/jpeg"
        case "png": "image/png"
        case "gif": "image/gif"
        case "heic": "image/heic"
        case "pdf": "application/pdf"
        case "txt", "md": "text/plain"
        case "csv": "text/csv"
        case "json": "application/json"
        default: "application/octet-stream"
        }
    }

    /// The file as a `data:` URL, the form `file.attach` takes.
    public var dataURL: String {
        "data:\(mimeType);base64,\(data.base64EncodedString())"
    }
}
