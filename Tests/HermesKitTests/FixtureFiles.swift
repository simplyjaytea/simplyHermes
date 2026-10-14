import Foundation
import HermesKit

/// One recorded frame from `Fixtures/*.jsonl`, decoded as an ``RPCFrame``.
struct FixtureRecord {
    /// File name, such as `chat_simple.jsonl`.
    let file: String
    /// 1-based line number in the file.
    let line: Int
    /// `in` (server to client) or `out` (client to server).
    let dir: String
    /// The decoded frame.
    let frame: RPCFrame
    /// For a client request: its method. For a response: the method of the request it answers.
    let method: String?
}

/// Loads the recorded protocol fixtures. The directory is found relative to this file, so it works from any cwd.
enum FixtureFiles {
    /// `Fixtures/` at the repository root.
    static var directory: URL {
        // Tests/HermesKitTests/FixtureFiles.swift -> repo root
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures")
    }

    /// Every frame of every fixture, in file order. Throws on the first line that does not decode.
    static func load() throws -> [FixtureRecord] {
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".jsonl") }
            .sorted()
        var records: [FixtureRecord] = []
        for file in files {
            let text = try String(contentsOf: directory.appendingPathComponent(file), encoding: .utf8)
            var methodByID: [RPCID: String] = [:]
            for (offset, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: true).enumerated() {
                let lineNumber = offset + 1
                let envelope: FixtureLine
                do {
                    envelope = try JSONDecoder().decode(FixtureLine.self, from: Data(rawLine.utf8))
                } catch {
                    throw FixtureLoadError("\(file):\(lineNumber) does not decode as a fixture line: \(error)")
                }
                let method: String?
                switch envelope.frame {
                case .request(let request):
                    method = request.method
                    if envelope.dir == "out" { methodByID[request.id] = request.method }
                case .response(let response):
                    method = response.id.flatMap { methodByID[$0] }
                default:
                    method = nil
                }
                records.append(
                    FixtureRecord(
                        file: file, line: lineNumber, dir: envelope.dir, frame: envelope.frame, method: method))
            }
        }
        return records
    }
}

extension RPCFrame {
    /// The response, when this frame is one. Test helper.
    var response: RPCResponse? {
        guard case .response(let response) = self else { return nil }
        return response
    }
}

/// A `{"dir","frame"}` line. Other keys (`i`, `ms`, `socket`) are ignored.
private struct FixtureLine: Decodable {
    let dir: String
    let frame: RPCFrame
}

/// A fixture could not be loaded.
struct FixtureLoadError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
