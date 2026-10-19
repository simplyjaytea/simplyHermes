import Foundation

/// One value kept as a JSON file that every save replaces atomically.
///
/// The app, its widgets and the Share extension hand small files to each other through the shared container.
/// A missing or damaged file reads as `nil`, so a reader never has to deal with a half-written file.
public struct JSONFileStore<Value: Codable & Sendable>: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public init(directory: URL, fileName: String) {
        fileURL = directory.appendingPathComponent(fileName)
    }

    public func load() -> Value? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? Self.decoder.decode(Value.self, from: data)
    }

    public func save(_ value: Value) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(value).write(to: fileURL, options: .atomic)
    }

    public func remove() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
