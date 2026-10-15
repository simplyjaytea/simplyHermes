import Foundation

/// Where the user stopped reading a session, so reopening it scrolls back there.
public struct ReadingPosition: Sendable, Equatable, Codable {
    /// Id of the transcript item at the top of the screen, such as `row-157`.
    public var anchorItemID: String
    /// Durable row id of that item, when it has one. Survives a rebuilt transcript where item ids change.
    public var anchorRowID: Int?
    /// Points the anchor item is scrolled past the top edge (0 when its top is flush).
    public var offset: Double
    /// True when the user was at the bottom, following new messages. Reopening then jumps to the end.
    public var atBottom: Bool
    /// When it was saved.
    public var updatedAt: Date

    /// Creates a position.
    public init(
        anchorItemID: String, anchorRowID: Int? = nil, offset: Double = 0, atBottom: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.anchorItemID = anchorItemID
        self.anchorRowID = anchorRowID
        self.offset = offset
        self.atBottom = atBottom
        self.updatedAt = updatedAt
    }
}
