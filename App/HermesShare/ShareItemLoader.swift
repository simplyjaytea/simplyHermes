import Foundation
import HermesKit
import ImageIO
import UniformTypeIdentifiers
import os

/// What one shared item turned into.
enum SharedItem: Sendable {
    case text(String)
    case link(URL)
    case file(SharePayload.Attachment)
    /// Left out, with a calm sentence that says why.
    case refused(String)
    /// Nothing to add and nothing to say.
    case skipped
}

/// Reads the things another app shares and stages their files in the share's outbox folder.
///
/// An extension has about 120 MB of memory, so photos are shrunk with ImageIO while they are read (the full picture
/// is never decoded) and other files are copied from disk to disk. Limits come from ``ShareLimits``.
struct ShareItemLoader: Sendable {
    let outbox: ShareOutbox
    let shareID: String
    private let budget = OSAllocatedUnfairLock(initialState: ShareBudget())
    private let leftOut = OSAllocatedUnfairLock(initialState: 0)

    init(outbox: ShareOutbox, shareID: String) {
        self.outbox = outbox
        self.shareID = shareID
    }

    /// Files that did not fit because the share already held the most it may.
    var filesLeftOut: Int { leftOut.withLock { $0 } }

    /// Loads one item. The order matters: a photo is a photo even when it also comes as a file, and a file wins over
    /// the link to it.
    @MainActor
    func load(_ provider: NSItemProvider) async -> SharedItem {
        let types = provider.registeredTypeIdentifiers.compactMap { UTType($0) }
        if let image = types.first(where: { $0.conforms(to: .image) }) {
            return await loadPhoto(provider, type: image)
        }
        let isFile = types.contains(.fileURL)
        let data = types.first { $0.conforms(to: .data) && !$0.conforms(to: .url) && !$0.conforms(to: .text) }
        if let data, isFile || !types.contains(where: { $0.conforms(to: .text) || $0.conforms(to: .url) }) {
            return await loadFile(provider, type: data)
        }
        if types.contains(where: { $0.conforms(to: .url) }) {
            return await loadLink(provider)
        }
        if let text = types.first(where: { $0.conforms(to: .text) }) {
            return await loadText(provider, type: text)
        }
        if let data {
            return await loadFile(provider, type: data)
        }
        return .skipped
    }

    // MARK: Photos

    @MainActor
    private func loadPhoto(_ provider: NSItemProvider, type: UTType) async -> SharedItem {
        let suggestedName = provider.suggestedName
        do {
            return try await withCheckedThrowingContinuation { continuation in
                provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, error in
                    guard let url else {
                        continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                        return
                    }
                    // The file is deleted when this handler returns, so everything happens here.
                    continuation.resume(returning: stagePhoto(at: url, suggestedName: suggestedName))
                }
            }
        } catch {
            return .refused("A photo could not be read.")
        }
    }

    private func stagePhoto(at url: URL, suggestedName: String?) -> SharedItem {
        let stem = URL(fileURLWithPath: suggestedName ?? url.lastPathComponent).deletingPathExtension()
            .lastPathComponent
        let fileName = (stem.isEmpty ? "Photo" : stem) + ".jpg"
        guard let jpeg = Self.shrunkJPEG(from: url) else { return .refused("\(fileName) could not be read.") }
        if let refusal = budget.withLock({ $0.admit(byteCount: jpeg.count) }) {
            return refuse(refusal, fileName: fileName)
        }
        do {
            return .file(try outbox.storeData(id: shareID, data: jpeg, fileName: fileName, kind: .image))
        } catch {
            return .refused("\(fileName) could not be saved.")
        }
    }

    /// The picture as a JPEG whose longest side is at most ``ShareLimits/maxImageSide``. Smaller pictures keep their
    /// size, and the orientation is applied.
    static func shrunkJPEG(from url: URL) -> Data? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let longest = max(width, height)
        let side = longest > 0 ? min(longest, ShareLimits.maxImageSide) : ShareLimits.maxImageSide
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: side,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary)
        else { return nil }
        let output = NSMutableData()
        let jpeg = UTType.jpeg.identifier as CFString
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, jpeg, 1, nil)
        else { return nil }
        let quality = [kCGImageDestinationLossyCompressionQuality: ShareLimits.jpegQuality] as CFDictionary
        CGImageDestinationAddImage(destination, image, quality)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    // MARK: Files

    @MainActor
    private func loadFile(_ provider: NSItemProvider, type: UTType) async -> SharedItem {
        do {
            return try await withCheckedThrowingContinuation { continuation in
                provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, error in
                    guard let url else {
                        continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                        return
                    }
                    continuation.resume(returning: stageFile(at: url))
                }
            }
        } catch {
            return .refused("A file could not be read.")
        }
    }

    /// Copies a file into the share, after checking it against the limits so a big file is never copied for nothing.
    private func stageFile(at url: URL) -> SharedItem {
        let name = url.lastPathComponent
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
        if values?.isDirectory == true {
            return .refused("\(name) is a folder, and folders cannot be shared.")
        }
        // Read the size here: URLResourceValues is not Sendable, so the lock's closure cannot capture it.
        // A file whose size cannot be read cannot be checked against the limits, so it is not taken.
        guard let byteCount = values?.fileSize else { return .refused("\(name) could not be read.") }
        if let refusal = budget.withLock({ $0.admit(byteCount: byteCount) }) {
            return refuse(refusal, fileName: name)
        }
        do {
            return .file(
                try outbox.storeFile(id: shareID, copying: url, fileName: name, kind: .forFile(named: name)))
        } catch {
            return .refused("\(name) could not be read.")
        }
    }

    private func refuse(_ refusal: ShareBudget.Refusal, fileName: String) -> SharedItem {
        if refusal == .tooMany {
            // A long selection would fill the sheet with notices, so they are counted and written as one.
            leftOut.withLock { $0 += 1 }
            return .skipped
        }
        return .refused(ShareBudget.notice(for: refusal, fileName: fileName))
    }

    // MARK: Links and text

    @MainActor
    private func loadLink(_ provider: NSItemProvider) async -> SharedItem {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                guard let url = item as? URL else {
                    continuation.resume(returning: .skipped)
                    return
                }
                continuation.resume(returning: url.isFileURL ? stageSecurityScoped(url) : .link(url))
            }
        }
    }

    /// A file shared as a link to a place on disk. The sender grants access for the length of the share.
    private func stageSecurityScoped(_ url: URL) -> SharedItem {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
        return stageFile(at: url)
    }

    @MainActor
    private func loadText(_ provider: NSItemProvider, type: UTType) async -> SharedItem {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { item, _ in
                continuation.resume(returning: textItem(from: item))
            }
        }
    }

    private func textItem(from item: (any NSSecureCoding)?) -> SharedItem {
        switch item {
        case let text as String:
            return .text(text)
        case let attributed as NSAttributedString:
            return .text(attributed.string)
        case let data as Data:
            return String(data: data, encoding: .utf8).map(SharedItem.text) ?? .skipped
        case let url as URL:
            return url.isFileURL ? stageSecurityScoped(url) : .link(url)
        default:
            return .skipped
        }
    }
}
