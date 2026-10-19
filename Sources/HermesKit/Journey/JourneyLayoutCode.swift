import Foundation

// Layout codes: a short piece of text that holds how the memory graph looks, so it can be copied, sent in a message
// and applied on another device (WP-52).
//
// Format "HJ1" (not the Desktop app's share format; the two do not read each other's codes):
//
//     code      = "HJ1." base64url(payload)            RFC 4648 section 5, no padding, A-Z a-z 0-9 - _
//     payload   = body check
//     body      = filter zoom scrub centerX centerY count placement*count
//     placement = node x y
//     check     = u16: the FNV-1a hash of the body, high half XOR low half
//
// All numbers are big endian. A code with no moved nodes is 20 characters long, and each moved node adds about 11.
//
//     filter   u8    0 All, 1 Used, 2 Learned
//     zoom     u16   (log2(zoom) - log2(0.5)) / (log2(8) - log2(0.5)) scaled to 0...65535
//     scrub    u16   the scrub position 0...1 scaled to 0...65535
//     centerX  i16   the pan centre, -1.25...1.25 layout units scaled to -32767...32767
//     centerY  i16   the same for y
//     count    u8    how many placements follow, 0...255 (an encoder keeps the first 255 in node order)
//     node     u32   the FNV-1a hash of the node id, so the code needs no node names
//     x, y     i16   the position of the node, scaled like the centre
//
// The version prefix lets a later layout change the body and still tell old codes from new ones. A decoder refuses a
// code with another prefix, text that is not exactly what the encoder writes (so every layout has one code), a length
// that does not fit `count`, a wrong check, and a filter it does not know. Whitespace anywhere in the pasted text is
// ignored, so a code that a chat app wrapped onto two lines still works. Numbers are rounded to the steps above, so a
// round trip is exact to better than one part in 20,000.

/// Turns a ``JourneyLayoutState`` into a layout code and back. See the header of this file for the format.
public enum JourneyLayoutCode {
    /// The text every code starts with.
    public static let versionPrefix = "HJ1."
    /// The most moved nodes one code carries.
    public static let maxPlacements = 255

    /// The settings a code holds. Node positions are held by hash until a graph says which nodes exist.
    public struct Decoded: Sendable, Equatable {
        /// Which nodes show.
        public var filter: JourneyFilter
        /// The scrub position, 0 to 1.
        public var scrub: Double
        /// Zoom and pan.
        public var viewport: JourneyViewport
        /// Moved nodes by ``JourneyLayoutCode/nodeKey(for:)``.
        public var placements: [UInt32: CGPoint]

        /// The state to show `graph` with: the code's settings, and the moved nodes the graph holds.
        public func state(for graph: JourneyGraph) -> JourneyLayoutState {
            var moved: [String: CGPoint] = [:]
            for node in graph.nodes {
                if let point = placements[JourneyLayoutCode.nodeKey(for: node.id)] { moved[node.id] = point }
            }
            return JourneyLayoutState(filter: filter, scrub: scrub, viewport: viewport, placements: moved)
        }
    }

    /// Why a piece of text is not a usable layout code.
    public enum Problem: Error, Sendable, Equatable {
        /// Nothing was typed or pasted.
        case empty
        /// The text does not start with `HJ1.` or any other version prefix.
        case notACode
        /// The text is a code of another version, such as `HJ2.`.
        case otherVersion(String)
        /// The code is cut short, mistyped or changed after it was made.
        case damaged

        /// One sentence for the sheet.
        public var message: String {
            switch self {
            case .empty: "Paste a layout code."
            case .notACode: "That is not a layout code. A code starts with \(JourneyLayoutCode.versionPrefix)"
            case .otherVersion(let version):
                "This code comes from a different version of the app (\(version)), so this version cannot read it."
            case .damaged: "The code is damaged or cut short. Copy it again from the start."
            }
        }
    }

    /// The key a node has inside a code: a hash of its id that never changes between launches.
    public static func nodeKey(for id: String) -> UInt32 { JourneyHash.fnv1a(id) }

    // MARK: - Encoding

    /// The code for `state`. The same state always gives the same code.
    public static func encode(_ state: JourneyLayoutState) -> String {
        var body: [UInt8] = [filterIndex(state.filter)]
        appendBigEndian(unsigned: zoomStep(state.viewport.zoom), to: &body)
        appendBigEndian(unsigned: unsignedStep(JourneyTimeline.clamp(state.scrub)), to: &body)
        appendBigEndian(signed: coordinateStep(state.viewport.center.x), to: &body)
        appendBigEndian(signed: coordinateStep(state.viewport.center.y), to: &body)
        let moved = state.placements.map { id, point in
            Placement(
                key: nodeKey(for: id), horizontal: coordinateStep(point.x), vertical: coordinateStep(point.y))
        }
        let kept = moved.sorted().prefix(maxPlacements)
        body.append(UInt8(kept.count))
        for placement in kept {
            appendBigEndian(unsigned: UInt16(placement.key >> 16), to: &body)
            appendBigEndian(unsigned: UInt16(placement.key & 0xFFFF), to: &body)
            appendBigEndian(signed: placement.horizontal, to: &body)
            appendBigEndian(signed: placement.vertical, to: &body)
        }
        let sum = check(of: body)
        appendBigEndian(unsigned: sum, to: &body)
        return versionPrefix + encodeBase64URL(body)
    }

    // MARK: - Decoding

    /// Reads a code. Throws a ``Problem`` for anything that is not a code made by ``encode(_:)``.
    public static func decode(_ text: String) throws -> Decoded {
        try parse(text).get()
    }

    /// What is wrong with `text` as a layout code, or nil when it is a good one. Text with nothing in it is
    /// ``Problem/empty``.
    public static func problem(with text: String) -> Problem? {
        if case .failure(let problem) = parse(text) { return problem }
        return nil
    }

    private static func parse(_ text: String) -> Result<Decoded, Problem> {
        let compact = text.filter { !$0.isWhitespace }
        guard !compact.isEmpty else { return .failure(.empty) }
        guard compact.hasPrefix(versionPrefix) else { return .failure(unknownPrefix(compact)) }
        guard let payload = decodeBase64URL(String(compact.dropFirst(versionPrefix.count))),
            payload.count >= minimumLength, (payload.count - minimumLength) % placementLength == 0
        else { return .failure(.damaged) }
        let body = Array(payload.dropLast(2))
        var checkReader = ByteReader(Array(payload.suffix(2)))
        guard checkReader.unsigned16() == check(of: body), let decoded = read(body) else {
            return .failure(.damaged)
        }
        return .success(decoded)
    }

    /// Tells a code of another version (`HJ2.`) from text that is not a code at all.
    private static func unknownPrefix(_ text: String) -> Problem {
        guard text.hasPrefix("HJ") else { return .notACode }
        let digits = text.dropFirst(2).prefix { $0.isASCII && $0.isNumber }
        let rest = text.dropFirst(2 + digits.count)
        return !digits.isEmpty && rest.hasPrefix(".") ? .otherVersion("HJ" + digits) : .notACode
    }

    private static func read(_ body: [UInt8]) -> Decoded? {
        var reader = ByteReader(body)
        guard let filterByte = reader.byte(), let chosen = filter(atIndex: filterByte),
            let zoomValue = reader.unsigned16(), let scrubValue = reader.unsigned16(),
            let centerX = reader.signed16(), let centerY = reader.signed16(), let count = reader.byte()
        else { return nil }
        var placements: [UInt32: CGPoint] = [:]
        for _ in 0..<Int(count) {
            guard let key = reader.unsigned32(), let across = reader.signed16(), let down = reader.signed16() else {
                return nil
            }
            placements[key] = CGPoint(x: coordinate(across), y: coordinate(down))
        }
        guard reader.isAtEnd else { return nil }
        let viewport = JourneyViewport(
            zoom: zoom(zoomValue), center: CGPoint(x: coordinate(centerX), y: coordinate(centerY)))
        return Decoded(
            filter: chosen, scrub: Double(scrubValue) / unsignedSteps, viewport: viewport, placements: placements)
    }

    // MARK: - Numbers

    /// A moved node, already rounded to code steps.
    private struct Placement: Comparable {
        var key: UInt32
        var horizontal: Int16
        var vertical: Int16

        static func < (left: Placement, right: Placement) -> Bool {
            (left.key, left.horizontal, left.vertical) < (right.key, right.horizontal, right.vertical)
        }
    }

    private static let unsignedSteps = 65_535.0
    private static let coordinateSteps = 32_767.0
    /// Filter + zoom + scrub + centre x + centre y + count + check.
    private static let minimumLength = 12
    /// Node hash + x + y.
    private static let placementLength = 8

    private static func filterIndex(_ filter: JourneyFilter) -> UInt8 {
        switch filter {
        case .all: 0
        case .used: 1
        case .learned: 2
        }
    }

    private static func filter(atIndex index: UInt8) -> JourneyFilter? {
        switch index {
        case 0: .all
        case 1: .used
        case 2: .learned
        default: nil
        }
    }

    private static func unsignedStep(_ unit: Double) -> UInt16 {
        UInt16((min(max(unit, 0), 1) * unsignedSteps).rounded())
    }

    private static func zoomStep(_ zoom: Double) -> UInt16 {
        let low = log2(JourneyViewport.zoomRange.lowerBound)
        let high = log2(JourneyViewport.zoomRange.upperBound)
        return unsignedStep((log2(JourneyViewport.clampZoom(zoom)) - low) / (high - low))
    }

    private static func zoom(_ step: UInt16) -> Double {
        let low = log2(JourneyViewport.zoomRange.lowerBound)
        let high = log2(JourneyViewport.zoomRange.upperBound)
        return pow(2, low + Double(step) / unsignedSteps * (high - low))
    }

    /// Not-a-number gives 0 and anything beyond the reach is cut to it.
    private static func coordinateStep(_ value: CGFloat) -> Int16 {
        let number = value.isNaN ? 0 : Double(value)
        let unit = min(max(number / JourneyViewport.reach, -1), 1)
        return Int16((unit * coordinateSteps).rounded())
    }

    private static func coordinate(_ step: Int16) -> Double {
        Double(step) / coordinateSteps * JourneyViewport.reach
    }

    // MARK: - Bytes

    private static func appendBigEndian(unsigned value: UInt16, to bytes: inout [UInt8]) {
        bytes.append(UInt8(value >> 8))
        bytes.append(UInt8(value & 0xFF))
    }

    private static func appendBigEndian(signed value: Int16, to bytes: inout [UInt8]) {
        appendBigEndian(unsigned: UInt16(bitPattern: value), to: &bytes)
    }

    private static func check(of body: [UInt8]) -> UInt16 {
        let hash = JourneyHash.fnv1a(bytes: body)
        return UInt16(hash >> 16) ^ UInt16(hash & 0xFFFF)
    }

    private static func encodeBase64URL(_ bytes: [UInt8]) -> String {
        Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// The bytes of base64url text, or nil when the text is not exactly what ``encodeBase64URL(_:)`` writes.
    private static func decodeBase64URL(_ text: String) -> [UInt8]? {
        guard !text.isEmpty, text.count % 4 != 1, text.utf8.allSatisfy(isBase64URL) else { return nil }
        let padding = String(repeating: "=", count: (4 - text.count % 4) % 4)
        let standard = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        guard let data = Data(base64Encoded: standard + padding) else { return nil }
        let decoded = [UInt8](data)
        return encodeBase64URL(decoded) == text ? decoded : nil
    }

    private static func isBase64URL(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"),
            UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "-"), UInt8(ascii: "_"):
            true
        default:
            false
        }
    }
}

/// Reads big-endian numbers from bytes. Every read returns nil at the end instead of trapping.
private struct ByteReader {
    private let bytes: [UInt8]
    private var position = 0

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    var isAtEnd: Bool { position == bytes.count }

    mutating func byte() -> UInt8? {
        guard position < bytes.count else { return nil }
        defer { position += 1 }
        return bytes[position]
    }

    mutating func unsigned16() -> UInt16? {
        guard let high = byte(), let low = byte() else { return nil }
        return UInt16(high) << 8 | UInt16(low)
    }

    mutating func signed16() -> Int16? {
        unsigned16().map { Int16(bitPattern: $0) }
    }

    mutating func unsigned32() -> UInt32? {
        guard let high = unsigned16(), let low = unsigned16() else { return nil }
        return UInt32(high) << 16 | UInt32(low)
    }
}
