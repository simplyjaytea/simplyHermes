/// Params of `image.attach_bytes`: an image sent as base64. The server queues it for the next turn.
public struct ImageAttachBytesParams: Sendable, Equatable, Codable {
    /// The live session id.
    public var sessionID: String
    /// Profile to scope the call to.
    public var profile: String?
    /// The image bytes, base64 encoded. The magic bytes decide the format.
    public var contentBase64: String
    /// File name. Only a hint for the extension.
    public var filename: String?

    /// Creates the params.
    public init(sessionID: String, profile: String? = nil, contentBase64: String, filename: String? = nil) {
        self.sessionID = sessionID
        self.profile = profile
        self.contentBase64 = contentBase64
        self.filename = filename
    }

    enum CodingKeys: String, CodingKey {
        case profile, filename
        case sessionID = "session_id"
        case contentBase64 = "content_base64"
    }
}

/// Result of `image.attach_bytes`. `attached` is false when the server refuses the image.
public struct AttachedImageResult: Sendable, Equatable, Codable {
    /// True when the image waits for the next turn.
    public var attached: Bool
    /// Why the image was refused, when it was.
    public var message: String?
}

/// Params of `pdf.attach`: a PDF sent as base64. The server renders its pages to images for the next turn.
public struct PdfAttachParams: Sendable, Equatable, Codable {
    /// The live session id.
    public var sessionID: String
    /// Profile to scope the call to.
    public var profile: String?
    /// The PDF bytes, base64 encoded.
    public var contentBase64: String
    /// File name of the PDF.
    public var filename: String?

    /// Creates the params.
    public init(sessionID: String, profile: String? = nil, contentBase64: String, filename: String? = nil) {
        self.sessionID = sessionID
        self.profile = profile
        self.contentBase64 = contentBase64
        self.filename = filename
    }

    enum CodingKeys: String, CodingKey {
        case profile, filename
        case sessionID = "session_id"
        case contentBase64 = "content_base64"
    }
}

/// Result of `pdf.attach`.
public struct PdfAttachResult: Sendable, Equatable, Codable {
    /// True when the pages wait for the next turn.
    public var attached: Bool
    /// How many pages were queued as images.
    public var pagesAttached: Int?

    enum CodingKeys: String, CodingKey {
        case attached
        case pagesAttached = "pages_attached"
    }
}

/// Params of `file.attach`: a file that is not an image, as a `data:` URL. The server stages it in the workspace.
public struct FileAttachParams: Sendable, Equatable, Codable {
    /// The live session id.
    public var sessionID: String
    /// Profile to scope the call to.
    public var profile: String?
    /// The file as a `data:` URL.
    public var dataURL: String
    /// Name the file keeps in the workspace.
    public var name: String

    /// Creates the params.
    public init(sessionID: String, profile: String? = nil, dataURL: String, name: String) {
        self.sessionID = sessionID
        self.profile = profile
        self.dataURL = dataURL
        self.name = name
    }

    enum CodingKeys: String, CodingKey {
        case profile, name
        case sessionID = "session_id"
        case dataURL = "data_url"
    }
}

/// Result of `file.attach`. The message must carry `refText`, or Hermes cannot read the file.
public struct FileAttachResult: Sendable, Equatable, Codable {
    /// True when the file is staged.
    public var attached: Bool
    /// Name of the staged file.
    public var name: String
    /// The `@file:` reference to put into the message.
    public var refText: String

    enum CodingKeys: String, CodingKey {
        case attached, name
        case refText = "ref_text"
    }
}
