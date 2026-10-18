import Foundation

/// Why a bot could not be exported or imported (WP-41).
public enum ProfileTransferError: Error, Sendable, Equatable {
    /// The export answered without an archive.
    case noArchive
    /// The server kept the archive at this path on its own disk. The phone cannot fetch it yet.
    case serverPath(String)
    /// The archive field is not base64, or it decodes to nothing.
    case invalidArchive
    /// The import answer neither says `ok: true` nor names the bot, so the bot may or may not exist.
    case unconfirmedImport

    /// The sentence to show.
    public var message: String {
        switch self {
        case .noArchive:
            "The server did not send the archive."
        case .serverPath(let path):
            "The server saved the archive at \(path). The phone cannot open files on the server yet."
        case .invalidArchive:
            "The archive from the server could not be read."
        case .unconfirmedImport:
            "The server did not confirm the import. Check the bot list before you try again."
        }
    }

    /// The sentence to show for any error from a profile export or import.
    public static func describe(_ error: any Error) -> String {
        if let transfer = error as? ProfileTransferError { return transfer.message }
        if let rpc = error as? RPCError { return rpc.message }
        if error is ConnectionUnavailable { return "The server is not reachable." }
        guard let rest = error as? RESTError else { return "The request failed." }
        switch rest {
        case .http(_, let detail?): return detail
        case .http(let status, nil): return "The server refused the request (HTTP \(status))."
        case .unauthorized: return "Sign in again to continue."
        case .rateLimited: return "The server is busy. Try again in a moment."
        case .transport: return "The server is not reachable."
        case .unexpectedContent, .decoding: return "The server sent an answer the app does not understand."
        }
    }
}

/// A profile archive as the phone keeps it, ready for the share sheet (WP-41).
///
/// UNTESTED LIVE. The contract does not describe the export's answer, so ``from(answer:)`` takes the shapes the server
/// could plausibly send: the archive as raw bytes, or a JSON object (or JSON string) with the archive as base64 under
/// `archive`, `data`, `base64` or `content`. A JSON answer with only a `path`, or with a path under `archive`,
/// means the server kept the file on its own disk, which the phone cannot fetch yet.
public struct ProfileArchive: Sendable, Equatable {
    /// The archive bytes.
    public var data: Data
    /// The extension to save under, from the bytes: `zip` for a zip file, `tar.gz` otherwise.
    public var fileExtension: String

    /// Wraps archive bytes.
    public init(data: Data) {
        self.data = data
        self.fileExtension = Self.fileExtension(for: data)
    }

    /// Reads an export answer. Throws ``ProfileTransferError`` when the answer holds no archive.
    ///
    /// Printable text that is neither JSON nor a long base64 string is refused rather than saved, so a status word is
    /// never written out as an archive. Anything with control bytes is taken as the archive itself.
    public static func from(answer: HTTPResponse) throws -> ProfileArchive {
        let body = answer.body
        guard !body.isEmpty else { throw ProfileTransferError.noArchive }
        if let object = try? JSONSerialization.jsonObject(with: body, options: [.fragmentsAllowed]) {
            if let text = object as? String {
                return try ProfileArchive(data: decodeBase64(text))
            }
            if let fields = object as? [String: Any] {
                for key in ["archive", "data", "base64", "content"] {
                    guard let text = fields[key] as? String else { continue }
                    // A leading slash is a path on the server's disk. Base64 of a gzip or zip never starts with one.
                    if text.hasPrefix("/") { throw ProfileTransferError.serverPath(text) }
                    return try ProfileArchive(data: decodeBase64(text))
                }
                if let path = fields["path"] as? String, !path.isEmpty { throw ProfileTransferError.serverPath(path) }
                throw ProfileTransferError.noArchive
            }
        }
        if isPrintable(body) {
            guard let text = String(data: body, encoding: .ascii), text.count >= 64, isBase64(text) else {
                throw ProfileTransferError.invalidArchive
            }
            return try ProfileArchive(data: decodeBase64(text))
        }
        return ProfileArchive(data: body)
    }

    /// True when every byte is printable ASCII or a line break. Archives hold control bytes, so they never pass.
    private static func isPrintable(_ data: Data) -> Bool {
        data.allSatisfy { ($0 >= 0x20 && $0 <= 0x7E) || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }
    }

    /// True when the text holds only base64 characters and line breaks.
    private static func isBase64(_ text: String) -> Bool {
        let alphabet = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/= \t\r\n")
        return text.allSatisfy { alphabet.contains($0) }
    }

    /// The folder every export writes into, under `root`. Its name is fixed, so a later sheet opening
    /// finds and clears the export of an earlier one.
    public static func exportFolder(in root: URL = FileManager.default.temporaryDirectory) -> URL {
        root.appendingPathComponent("hermes-bot-export", isDirectory: true)
    }

    /// Removes the export folder and the file in it, when there is one. Exports call this before they write,
    /// so the last export is gone before the next one is written.
    public static func removeExportFolder(in root: URL = FileManager.default.temporaryDirectory) throws {
        let folder = exportFolder(in: root)
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        try FileManager.default.removeItem(at: folder)
    }

    /// Writes the archive into the export folder under `root` and returns the file. The name comes from the profile.
    /// The folder is created when it is missing. Removing the last export is the caller's job, see
    /// ``removeExportFolder(in:)``.
    public func writeTemporaryFile(
        for profile: String, in root: URL = FileManager.default.temporaryDirectory
    ) throws -> URL {
        let folder = Self.exportFolder(in: root)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(Self.fileStem(for: profile) + "." + fileExtension)
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func decodeBase64(_ text: String) throws -> Data {
        guard let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters), !data.isEmpty else {
            throw ProfileTransferError.invalidArchive
        }
        return data
    }

    static func fileExtension(for data: Data) -> String {
        data.starts(with: [0x50, 0x4B, 0x03, 0x04]) ? "zip" : "tar.gz"
    }

    /// The profile name with anything a file name should not hold replaced by `-`.
    static func fileStem(for profile: String) -> String {
        let stem = profile.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? String($0) : "-" }.joined()
        return stem.isEmpty ? "profile" : stem
    }
}

/// What a profile import answered (WP-41). UNTESTED LIVE: the contract gives no response schema, so an import counts as
/// done only when the answer confirms it, with `ok: true` or a non-empty `name`.
public struct ProfileImportResult: Sendable, Equatable {
    /// The name the bot was created under, when the answer said so.
    public var name: String?

    /// Creates a result.
    public init(name: String? = nil) {
        self.name = name
    }

    /// Reads an import answer. Throws ``ProfileTransferError/unconfirmedImport`` unless the answer confirms the import
    /// and `ok` is not `false`.
    public static func from(answer: HTTPResponse) throws -> ProfileImportResult {
        let fields = (try? JSONSerialization.jsonObject(with: answer.body)) as? [String: Any]
        let name = (fields?["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let ok = fields?["ok"] as? Bool
        guard ok != false, name != nil || ok == true else { throw ProfileTransferError.unconfirmedImport }
        return ProfileImportResult(name: name)
    }
}
