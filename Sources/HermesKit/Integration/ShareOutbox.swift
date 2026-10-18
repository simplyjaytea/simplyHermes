import Foundation

/// What the Share extension accepts.
///
/// The extension runs with about 120 MB of memory, and the app holds the files in memory while it sends them, so
/// everything stays small.
public enum ShareLimits {
    /// Longest side of a shared photo, in pixels.
    public static let maxImageSide = 2048
    /// JPEG quality for shared photos.
    public static let jpegQuality = 0.8
    /// All shared files together, in bytes. The Share sheet states this limit.
    public static let maxTotalBytes = 25 * 1024 * 1024
    /// One file, in bytes: the most the composer sends, so a shared file never fails later at the chat.
    public static let maxFileBytes = ComposerAttachment.maxBytes
    /// Photos and files in one share.
    public static let maxAttachments = 5
    /// Longest message, in characters. Longer text is cut.
    public static let maxTextCharacters = 50_000

    /// The total size limit in megabytes, as the Share sheet writes it.
    public static var maxTotalMegabytes: Int { maxTotalBytes / (1024 * 1024) }

    /// The single-file limit in megabytes, as the Share sheet writes it.
    public static var maxFileMegabytes: Int { maxFileBytes / (1024 * 1024) }

    /// The sentence under the destination list.
    public static var summary: String {
        "Photos are shrunk to \(maxImageSide) pixels. Files can be \(maxFileMegabytes) MB each and "
            + "\(maxTotalMegabytes) MB in total."
    }
}

/// Counts shared files against ``ShareLimits`` one at a time, in the order they are loaded.
public struct ShareBudget: Equatable, Sendable {
    public enum Refusal: Equatable, Sendable {
        /// The share already holds the most files it may.
        case tooMany
        /// The file alone is over the single-file limit.
        case fileTooLarge
        /// The file would take the share over the total size limit.
        case tooLarge
    }

    public private(set) var usedBytes = 0
    public private(set) var count = 0

    public init() {}

    /// Counts a file. Returns why it does not fit, or `nil` when it was accepted.
    public mutating func admit(byteCount: Int) -> Refusal? {
        guard count < ShareLimits.maxAttachments else { return .tooMany }
        guard byteCount <= ShareLimits.maxFileBytes else { return .fileTooLarge }
        guard usedBytes + byteCount <= ShareLimits.maxTotalBytes else { return .tooLarge }
        usedBytes += byteCount
        count += 1
        return nil
    }

    /// One sentence for the many files left out once a share is full, so the sheet is not filled with notices.
    public static func overflowNotice(leftOut: Int) -> String {
        let files = leftOut == 1 ? "1 more file was" : "\(leftOut) more files were"
        return "\(files) left out. You can share up to \(ShareLimits.maxAttachments) files at once."
    }

    /// The calm sentence the Share sheet shows for a file that was left out.
    public static func notice(for refusal: Refusal, fileName: String) -> String {
        switch refusal {
        case .tooMany:
            "\(fileName) was left out. You can share up to \(ShareLimits.maxAttachments) files at once."
        case .fileTooLarge:
            "\(fileName) was left out. A file can be \(ShareLimits.maxFileMegabytes) MB at most."
        case .tooLarge:
            "\(fileName) was left out. Files can be \(ShareLimits.maxTotalMegabytes) MB in total."
        }
    }
}

/// A file that waits in a share's folder.
public struct ShareAttachment: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case image
        case pdf
        case file

        /// PDF or plain file, from the file name. Photos are decided by the loader, which converts them.
        public static func forFile(named name: String) -> Kind {
            URL(fileURLWithPath: name).pathExtension.lowercased() == "pdf" ? .pdf : .file
        }
    }

    public var kind: Kind
    /// The name the chat shows.
    public var fileName: String
    /// The name inside the share's `files` folder. Always a single path component.
    public var storedName: String
    public var byteCount: Int

    public init(kind: Kind, fileName: String, storedName: String, byteCount: Int) {
        self.kind = kind
        self.fileName = fileName
        self.storedName = storedName
        self.byteCount = byteCount
    }

    /// The composer attachment for this file once its bytes are read.
    public func composerAttachment(data: Data) -> ComposerAttachment {
        let composerKind: ComposerAttachment.Kind =
            switch kind {
            case .image: .image
            case .pdf: .pdf
            case .file: .file
            }
        return ComposerAttachment(kind: composerKind, name: fileName, data: data)
    }
}

/// One share, as the extension hands it to the app: where it goes, the message, and the files that go with it.
public struct SharePayload: Codable, Equatable, Sendable, Identifiable {
    public enum Destination: Codable, Equatable, Sendable {
        case newChat
        case chat(sessionID: String)
    }

    public typealias Attachment = ShareAttachment

    public var id: String
    public var createdAt: Date
    public var destination: Destination
    /// The note and the shared text and links, already joined (see ``ShareMessage``).
    public var text: String
    public var attachments: [Attachment]

    public init(
        id: String, createdAt: Date, destination: Destination, text: String, attachments: [Attachment] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.destination = destination
        self.text = text
        self.attachments = attachments
    }
}

public enum ShareOutboxError: Error, Equatable, Sendable {
    /// The id is empty, too long, or holds a character that is not safe in a folder name.
    case invalidID
}

/// The folder where the Share extension leaves shares for the app.
///
/// Each share has its own folder, `<id>/files/<n>-<name>` for the files and `<id>/payload.json` for the message. The
/// extension writes `payload.json` last, so a folder without it is a share that is still being built (or was
/// abandoned) and the app ignores it. The extension never opens a connection; the app sends the message.
public struct ShareOutbox: Sendable {
    public static let folderName = "ShareOutbox"
    public static let payloadFileName = "payload.json"
    public static let filesFolderName = "files"
    /// A finished share nobody collected is dropped after this long.
    public static let maxAge: TimeInterval = 7 * 24 * 3600
    /// A share that never got its `payload.json` is cleaned up after this long.
    public static let stagingAge: TimeInterval = 24 * 3600
    /// Longest file name kept, in characters, extension included.
    public static let maxFileNameLength = 80

    /// A place in a share's `files` folder for one file.
    public struct Slot: Equatable, Sendable {
        public var url: URL
        public var displayName: String
        public var storedName: String
    }

    public let root: URL

    /// - Parameter directory: the shared integration folder, see ``SharedContainer``.
    public init(directory: URL) {
        root = directory.appendingPathComponent(Self.folderName, isDirectory: true)
    }

    // MARK: Ids and names

    public static func makeID() -> String {
        UUID().uuidString.lowercased()
    }

    /// Ids name folders and travel in URLs, so they are short and plain: ASCII letters, digits, `-` and `_`.
    public static func isValidID(_ id: String) -> Bool {
        guard (1...64).contains(id.count) else { return false }
        return id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    /// A file name that is safe inside the outbox: no folders, no control characters, no leading dots.
    public static func safeFileName(_ name: String, fallback: String = "file") -> String {
        let last = name.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? ""
        var cleaned = String(last.unicodeScalars.filter { !isControl($0) }).trimmingCharacters(in: .whitespaces)
        while cleaned.hasPrefix(".") { cleaned.removeFirst() }
        guard !cleaned.isEmpty else { return fallback }
        guard cleaned.count > maxFileNameLength else { return cleaned }
        let pathExtension = URL(fileURLWithPath: cleaned).pathExtension
        guard !pathExtension.isEmpty, pathExtension.count < 12 else { return String(cleaned.prefix(maxFileNameLength)) }
        let stemLength = maxFileNameLength - pathExtension.count - 1
        let stem = String(cleaned.dropLast(pathExtension.count + 1).prefix(stemLength))
        return stem + "." + pathExtension
    }

    private static func isControl(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value < 0x20 || scalar.value == 0x7F
    }

    // MARK: Writing (the extension)

    public func folder(for id: String) -> URL {
        root.appendingPathComponent(id, isDirectory: true)
    }

    public func filesFolder(for id: String) -> URL {
        folder(for: id).appendingPathComponent(Self.filesFolderName, isDirectory: true)
    }

    /// Creates the share's folders. Call this before the first file.
    public func prepare(id: String) throws {
        guard Self.isValidID(id) else { throw ShareOutboxError.invalidID }
        try FileManager.default.createDirectory(at: filesFolder(for: id), withIntermediateDirectories: true)
    }

    /// Picks a name for the next file of a share. Nothing is written yet.
    public func reserve(id: String, fileName: String) throws -> Slot {
        guard Self.isValidID(id) else { throw ShareOutboxError.invalidID }
        let displayName = Self.safeFileName(fileName)
        let folder = filesFolder(for: id)
        let existing = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        var index = existing.count + 1
        while existing.contains(where: { $0.hasPrefix("\(index)-") }) { index += 1 }
        let storedName = "\(index)-\(displayName)"
        return Slot(url: folder.appendingPathComponent(storedName), displayName: displayName, storedName: storedName)
    }

    /// The attachment record for a file written to `slot`, with its size read from disk.
    public func attachment(for slot: Slot, kind: SharePayload.Attachment.Kind) -> SharePayload.Attachment {
        let size = (try? slot.url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        return SharePayload.Attachment(
            kind: kind, fileName: slot.displayName, storedName: slot.storedName, byteCount: size)
    }

    /// Copies a file into the share.
    public func storeFile(
        id: String, copying source: URL, fileName: String, kind: SharePayload.Attachment.Kind
    ) throws -> SharePayload.Attachment {
        let slot = try reserve(id: id, fileName: fileName)
        try FileManager.default.copyItem(at: source, to: slot.url)
        return attachment(for: slot, kind: kind)
    }

    /// Writes bytes into the share as a file.
    public func storeData(
        id: String, data: Data, fileName: String, kind: SharePayload.Attachment.Kind
    ) throws -> SharePayload.Attachment {
        let slot = try reserve(id: id, fileName: fileName)
        try data.write(to: slot.url, options: .atomic)
        return attachment(for: slot, kind: kind)
    }

    /// Deletes a file that was written but not kept, for instance because it was over the limit.
    public func discard(_ slot: Slot) {
        try? FileManager.default.removeItem(at: slot.url)
    }

    /// Publishes the share. Written last, so the app never sees a share without its files.
    public func commit(_ payload: SharePayload) throws {
        guard Self.isValidID(payload.id) else { throw ShareOutboxError.invalidID }
        try store(for: payload.id).save(payload)
    }

    // MARK: Reading (the app)

    /// Finished shares, oldest first.
    public func pending() -> [SharePayload] {
        folders().compactMap { payload(id: $0.lastPathComponent) }
            .sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }

    /// One finished share, or `nil` when it is missing, unfinished or damaged.
    public func payload(id: String) -> SharePayload? {
        guard Self.isValidID(id), let payload = store(for: id).load(), payload.id == id else { return nil }
        return payload
    }

    /// The bytes of one of a share's files.
    public func data(of attachment: SharePayload.Attachment, in id: String) -> Data? {
        let name = attachment.storedName
        guard Self.isValidID(id), !name.isEmpty, name != ".", name != "..", !name.contains("/") else { return nil }
        return try? Data(contentsOf: filesFolder(for: id).appendingPathComponent(name))
    }

    /// Deletes a share and its files.
    public func remove(id: String) {
        guard Self.isValidID(id) else { return }
        try? FileManager.default.removeItem(at: folder(for: id))
    }

    /// Deletes shares nobody collected and shares that were never finished.
    public func purge(now: Date) {
        for folder in folders(includingInvalid: true) {
            let id = folder.lastPathComponent
            if let payload = payload(id: id) {
                if now.timeIntervalSince(payload.createdAt) > Self.maxAge { remove(id: id) }
                continue
            }
            let modified = (try? folder.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            if let modified, now.timeIntervalSince(modified) > Self.stagingAge {
                try? FileManager.default.removeItem(at: folder)
            }
        }
    }

    private func store(for id: String) -> JSONFileStore<SharePayload> {
        JSONFileStore(directory: folder(for: id), fileName: Self.payloadFileName)
    }

    private func folders(includingInvalid: Bool = false) -> [URL] {
        let all = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return all.filter { includingInvalid || Self.isValidID($0.lastPathComponent) }
    }
}
