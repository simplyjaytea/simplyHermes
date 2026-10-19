import Foundation
import HermesKit
import Testing

/// Share codes for the graph view (WP-52): the format in the header of `JourneyLayoutCode.swift`, round trips, and
/// every kind of bad input. The known answers were computed with a separate script that follows the documented
/// format, not with the code under test.
@Suite struct JourneyLayoutCodeTests {
    private let defaultCode = "HJ1.AEAA__8AAAAAAPZ6"
    private let movedCode = "HJ1.AoAAgAAzM-ZnAf0MUIcZmZmaCgw"

    private func movedState() -> JourneyLayoutState {
        JourneyLayoutState(
            filter: .learned, scrub: 0.5, viewport: JourneyViewport(zoom: 2, center: CGPoint(x: 0.5, y: -0.25)),
            placements: ["x": CGPoint(x: 0.25, y: -1)])
    }

    private func graph(_ ids: [String]) -> JourneyGraph {
        JourneyGraph(nodes: ids.map { JourneyNode(id: $0) })
    }

    // MARK: Format

    @Test func knownAnswers() throws {
        #expect(JourneyLayoutCode.versionPrefix == "HJ1.")
        #expect(JourneyLayoutCode.encode(JourneyLayoutState()) == defaultCode)
        #expect(JourneyLayoutCode.encode(movedState()) == movedCode)
        let state = try JourneyLayoutCode.decode(movedCode).state(for: graph(["x", "y"]))
        #expect(state.filter == .learned)
        #expect(abs(state.scrub - 0.5) < 1e-4 && abs(state.viewport.zoom - 2) < 1e-3)
        #expect(state.placements.keys.sorted() == ["x"])
    }

    @Test func aCodeWithoutMovedNodesIsTwentyCharactersLong() {
        #expect(defaultCode.count == 20)
        let one = JourneyLayoutCode.encode(movedState())
        #expect(one.count == 31, "each moved node adds about eleven characters")
    }

    /// Builds a code by hand from the documented layout, so the decoder is checked against the document.
    private func handMade(_ body: [UInt8]) -> String {
        var hash: UInt32 = 2_166_136_261
        for byte in body {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        let check = UInt16(hash >> 16) ^ UInt16(hash & 0xFFFF)
        let payload = body + [UInt8(check >> 8), UInt8(check & 0xFF)]
        let text = Data(payload).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "HJ1." + text
    }

    @Test func decoderFollowsTheDocumentedFormat() throws {
        // filter Used, zoom step 0 (0.5), scrub 0, centre (-32767, 32767) steps, one moved node.
        let key = JourneyLayoutCode.nodeKey(for: "m")
        let body: [UInt8] =
            [1, 0, 0, 0, 0, 0x80, 0x01, 0x7F, 0xFF, 1]
            + [UInt8(key >> 24), UInt8((key >> 16) & 0xFF), UInt8((key >> 8) & 0xFF), UInt8(key & 0xFF)]
            + [0x00, 0x00, 0x7F, 0xFF]
        let decoded = try JourneyLayoutCode.decode(handMade(body))
        #expect(decoded.filter == .used && decoded.scrub == 0)
        #expect(decoded.viewport.zoom == 0.5)
        // The pan target is 1.25 away on both axes, so the viewport pulls it back to its reach of 1.25.
        let center = decoded.viewport.center
        #expect(
            abs(Double(center.x) + 1.25 / 2.0.squareRoot()) < 1e-6
                && abs(Double(center.y) - 1.25 / 2.0.squareRoot()) < 1e-6)
        let moved = try #require(decoded.placements[key])
        #expect(moved.x == 0 && abs(Double(moved.y) - 1.25) < 1e-9)
    }

    @Test func nodeKeysNeverChange() {
        #expect(JourneyLayoutCode.nodeKey(for: "x") == 4_245_442_695)
        #expect(JourneyLayoutCode.nodeKey(for: "") == 2_166_136_261)
    }

    // MARK: Round trips

    @Test func roundTripKeepsFilterScrubZoomPanAndMovedNodes() throws {
        for filter in JourneyFilter.allCases {
            let state = JourneyLayoutState(
                filter: filter, scrub: 0.37, viewport: JourneyViewport(zoom: 3.3, center: CGPoint(x: -0.4, y: 0.9)),
                placements: [
                    "alpha": CGPoint(x: 0.1, y: 0.2), "memory:memory:0:aa": CGPoint(x: -0.7, y: 0.65),
                    "gamma": CGPoint(x: 1.2, y: -1.2),
                ])
            let known = graph(["alpha", "memory:memory:0:aa", "gamma", "unmoved"])
            let back = try JourneyLayoutCode.decode(JourneyLayoutCode.encode(state)).state(for: known)
            #expect(back.filter == filter)
            #expect(abs(back.scrub - 0.37) < 1e-4)
            #expect(abs(back.viewport.zoom / 3.3 - 1) < 1e-3)
            #expect(
                abs(Double(back.viewport.center.x) + 0.4) < 1e-4 && abs(Double(back.viewport.center.y) - 0.9) < 1e-4)
            #expect(Set(back.placements.keys) == ["alpha", "memory:memory:0:aa", "gamma"])
            for (id, point) in state.placements {
                let got = try #require(back.placements[id])
                #expect(abs(Double(got.x - point.x)) < 1e-4 && abs(Double(got.y - point.y)) < 1e-4, "\(id)")
            }
        }
    }

    @Test func zoomAndScrubEndpointsSurvive() throws {
        for zoom in [0.5, 8.0] {
            for scrub in [0.0, 1.0] {
                let state = JourneyLayoutState(scrub: scrub, viewport: JourneyViewport(zoom: zoom))
                let back = try JourneyLayoutCode.decode(JourneyLayoutCode.encode(state)).state(for: JourneyGraph())
                #expect(abs(back.viewport.zoom / zoom - 1) < 1e-9 && back.scrub == scrub)
            }
        }
    }

    @Test func sameStateAlwaysMakesTheSameCode() {
        var forward: [String: CGPoint] = [:]
        var backward: [String: CGPoint] = [:]
        let ids = (0..<40).map { "node-\($0)" }
        for id in ids { forward[id] = CGPoint(x: Double(id.count) / 20, y: -0.3) }
        for id in ids.reversed() { backward[id] = CGPoint(x: Double(id.count) / 20, y: -0.3) }
        let first = JourneyLayoutCode.encode(JourneyLayoutState(placements: forward))
        let second = JourneyLayoutCode.encode(JourneyLayoutState(placements: backward))
        #expect(first == second)
        #expect(first == JourneyLayoutCode.encode(JourneyLayoutState(placements: forward)))
    }

    @Test func movedNodesThatTheGraphLacksAreLeftOut() throws {
        let decoded = try JourneyLayoutCode.decode(JourneyLayoutCode.encode(movedState()))
        #expect(decoded.placements.count == 1)
        #expect(decoded.state(for: JourneyGraph()).placements.isEmpty)
        #expect(decoded.state(for: graph(["y", "z"])).placements.isEmpty)
        #expect(decoded.state(for: graph(["x"])).placements.count == 1)
    }

    @Test func aCodeCarriesAtMost255MovedNodes() throws {
        var many: [String: CGPoint] = [:]
        for index in 0..<300 { many["node-\(index)"] = CGPoint(x: 0.1, y: 0.1) }
        let decoded = try JourneyLayoutCode.decode(JourneyLayoutCode.encode(JourneyLayoutState(placements: many)))
        #expect(JourneyLayoutCode.maxPlacements == 255 && decoded.placements.count == 255)
    }

    @Test func numbersOutOfRangeAreClampedNotTrusted() throws {
        let wild: [String: CGPoint] = [
            "nan": CGPoint(x: CGFloat.nan, y: 0), "far": CGPoint(x: 99, y: -99),
            "inf": CGPoint(x: CGFloat.infinity, y: -CGFloat.infinity),
        ]
        let state = JourneyLayoutState(
            scrub: .nan, viewport: JourneyViewport(zoom: .infinity, center: CGPoint(x: .nan, y: 1e9)), placements: wild)
        let back = try JourneyLayoutCode.decode(JourneyLayoutCode.encode(state)).state(
            for: graph(["nan", "far", "inf"]))
        #expect(back.scrub == 1 && back.viewport.zoom == 8)
        #expect(back.placements["nan"] == CGPoint(x: 0, y: 0))
        #expect(abs(Double(try #require(back.placements["far"]).x) - 1.25) < 1e-9)
        #expect(abs(Double(try #require(back.placements["far"]).y) + 1.25) < 1e-9)
        #expect(back.placements["inf"] == CGPoint(x: 1.25, y: -1.25))
    }

    // MARK: Bad input

    @Test func emptyAndNonCodesAreTold() {
        #expect(JourneyLayoutCode.problem(with: "") == .empty)
        #expect(JourneyLayoutCode.problem(with: "  \n\t ") == .empty)
        for text in ["hello", "HJ", "HJ1", "hj1.AEAA__8AAAAAAPZ6", "HJ.AEAA__8AAAAAAPZ6", "HJx.AEAA", "J1.AEAA", "🙂"] {
            #expect(JourneyLayoutCode.problem(with: text) == .notACode, "\(text)")
        }
    }

    @Test func codesOfAnotherVersionAreNamed() {
        #expect(JourneyLayoutCode.problem(with: "HJ2.AEAA__8AAAAAAPZ6") == .otherVersion("HJ2"))
        #expect(JourneyLayoutCode.problem(with: "HJ10.xyz") == .otherVersion("HJ10"))
        #expect(JourneyLayoutCode.problem(with: "HJ0.") == .otherVersion("HJ0"))
        #expect(JourneyLayoutCode.Problem.otherVersion("HJ2").message.contains("HJ2"))
    }

    @Test func damagedCodesAreRejected() {
        let damaged = [
            "HJ1.", "HJ1.!!!!", "HJ1.AEAA__8AAAAAAPZ", "HJ1.AEAA__8AAAAAAPZ6AAAA", "HJ1.AEAA__8AAAAAAPZ7",
            "HJ1.AEAA//8AAAAAAPZ6", "HJ1.AEAA__8AAAAAAPZ6==", "HJ1.AEAA__8AAAAAAPZ6🙂", "HJ1.AEAA__8A AAAPZ6!",
            "HJ1.A", "HJ1.AAAAAAAAAAAAAAAA", "HJ1.AEAA__8AAAAAAPZ6.AEAA__8AAAAAAPZ6",
        ]
        for text in damaged {
            #expect(JourneyLayoutCode.problem(with: text) == .damaged, "\(text)")
            #expect(throws: JourneyLayoutCode.Problem.damaged) { try JourneyLayoutCode.decode(text) }
        }
    }

    @Test func aWrongFilterByteIsDamage() {
        // A filter of 3 with a correct check: only the filter itself is wrong.
        let body: [UInt8] = [3, 0x40, 0x00, 0xFF, 0xFF, 0, 0, 0, 0, 0]
        #expect(JourneyLayoutCode.problem(with: handMade(body)) == .damaged)
        #expect(JourneyLayoutCode.problem(with: handMade([0] + body.dropFirst())) == nil)
    }

    @Test func aCountThatDoesNotMatchTheLengthIsDamage() {
        let base: [UInt8] = [0, 0x40, 0x00, 0xFF, 0xFF, 0, 0, 0, 0]
        #expect(JourneyLayoutCode.problem(with: handMade(base + [1])) == .damaged, "count 1 but no node follows")
        #expect(JourneyLayoutCode.problem(with: handMade(base + [0, 9, 9, 9, 9, 9, 9, 9, 9])) == .damaged)
        #expect(JourneyLayoutCode.problem(with: handMade(base + [0])) == nil)
    }

    @Test func whitespaceInsideAPastedCodeIsIgnored() throws {
        let plain = try JourneyLayoutCode.decode(movedCode)
        let wrapped = "  \(movedCode.prefix(10))\r\n\(movedCode.dropFirst(10).prefix(9))\t \(movedCode.dropFirst(19))\n"
        #expect(try JourneyLayoutCode.decode(wrapped) == plain)
        #expect(JourneyLayoutCode.problem(with: " \(defaultCode) ") == nil)
    }

    @Test func everyShorterPieceOfACodeIsRejected() {
        for code in [defaultCode, movedCode] {
            for length in 0..<code.count {
                let piece = String(code.prefix(length))
                #expect(JourneyLayoutCode.problem(with: piece) != nil, "\(piece)")
            }
        }
    }

    @Test func aChangedCharacterIsCaught() {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        var tried = 0
        var accepted = 0
        for code in [defaultCode, movedCode] {
            let characters = Array(code)
            for index in JourneyLayoutCode.versionPrefix.count..<characters.count {
                for replacement in alphabet where replacement != characters[index] {
                    var changed = characters
                    changed[index] = replacement
                    tried += 1
                    if JourneyLayoutCode.problem(with: String(changed)) == nil { accepted += 1 }
                }
            }
        }
        // The check is 16 bits, so about one change in 65,000 slips through; none is expected in this fixed set.
        #expect(tried > 2_000 && accepted <= 1, "\(accepted) of \(tried) changes were accepted")
    }

    @Test func spareBitsAtTheEndMustBeZero() {
        // 20 bytes make 27 characters; the last one holds 4 data bits and 2 spare bits that must be 0.
        #expect(movedCode.hasSuffix("w"))
        for spare in ["x", "y", "z"] {
            #expect(JourneyLayoutCode.problem(with: String(movedCode.dropLast()) + spare) == .damaged)
        }
    }

    @Test func randomTextNeverCrashesTheDecoder() {
        var generator = SeededGenerator(seed: 52)
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        var accepted = 0
        for round in 0..<4_000 {
            var text: String
            switch round % 4 {
            case 0:
                let length = Int.random(in: 0...90, using: &generator)
                text = "HJ1." + String((0..<length).map { _ in alphabet.randomElement(using: &generator) ?? "A" })
            case 1:
                let length = Int.random(in: 0...40, using: &generator)
                text = String(
                    (0..<length).compactMap { _ in Unicode.Scalar(UInt32.random(in: 0x20...0x2FFF, using: &generator)) }
                        .map(Character.init))
            case 2:
                var characters = Array(round % 8 < 4 ? defaultCode : movedCode)
                for _ in 0..<Int.random(in: 1...3, using: &generator) {
                    characters[Int.random(in: 0..<characters.count, using: &generator)] =
                        alphabet.randomElement(using: &generator) ?? "A"
                }
                text = String(characters)
            default:
                let nodes = Int.random(in: 0...3, using: &generator)
                var body: [UInt8] = [UInt8.random(in: 0...4, using: &generator)]
                body += (0..<8).map { _ in UInt8.random(in: 0...255, using: &generator) }
                body.append(UInt8(nodes))
                body += (0..<(8 * nodes)).map { _ in UInt8.random(in: 0...255, using: &generator) }
                text = handMade(body)
            }
            let problem = JourneyLayoutCode.problem(with: text)
            guard problem == nil else { continue }
            accepted += 1
            guard let decoded = try? JourneyLayoutCode.decode(text) else {
                Issue.record("problem(with:) accepted \(text) but decode threw")
                continue
            }
            #expect((0.0...1.0).contains(decoded.scrub))
            #expect(JourneyViewport.zoomRange.contains(decoded.viewport.zoom))
            let center = decoded.viewport.center
            #expect((Double(center.x * center.x + center.y * center.y)).squareRoot() <= JourneyViewport.reach + 1e-9)
            #expect(decoded.placements.count <= JourneyLayoutCode.maxPlacements)
        }
        #expect(accepted > 500, "the structured inputs should get through: \(accepted)")
    }

    @Test func everyProblemHasAReadableMessage() {
        let problems: [JourneyLayoutCode.Problem] = [.empty, .notACode, .otherVersion("HJ3"), .damaged]
        for problem in problems {
            #expect(problem.message.hasSuffix(".") || problem.message.hasSuffix("HJ1."), "\(problem.message)")
        }
        #expect(JourneyLayoutCode.Problem.notACode.message.contains("HJ1."))
    }
}
