import Foundation

/// An image this chat generated, found in a finished image tool call (WP-36).
public struct ChatArtifact: Identifiable, Sendable, Equatable {
    /// The tool row's id. Jump-back scrolls the transcript to it.
    public let id: String
    /// The image as the server named it: a path under the media roots, or a URL.
    public let image: String
}

/// Finds the artifacts in a transcript. The gallery lists these, and nothing else (plan Q30, WP-36).
public enum ChatArtifacts {
    /// Every finished image tool call in the transcript, in order.
    public static func all(in items: [TranscriptItem]) -> [ChatArtifact] {
        items.compactMap { item in
            guard case .tool(let entry) = item.content, entry.phase == .completed,
                let image = image(toolName: entry.name, result: entry.result)
            else { return nil }
            return ChatArtifact(id: item.id, image: image)
        }
    }

    /// The image a tool call produced, or nil. Only image tools count, and a result that reports `success: false`
    /// produced nothing.
    public static func image(toolName: String, result: JSONValue?) -> String? {
        guard toolName.lowercased().contains("image"), let object = result?.objectValue else { return nil }
        if object["success"]?.boolValue == false { return nil }
        return object["image"]?.stringValue
    }
}
