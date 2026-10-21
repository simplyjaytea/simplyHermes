import Foundation
import HermesKit
import Testing

/// The export body the contract's ProfileExport takes. The app's client sends the same two fields.
private struct ExportBody: Encodable, Sendable {
    var output = ""
    var extraFiles: [String: String] = [:]
}

/// Describes an answer for a failure message: its status, its type and the shape of its body. For JSON it names each
/// key and what its value is. A string shows its length, its first eight characters and any character outside base64,
/// never the rest, so no archive content reaches the log.
private func shape(of answer: HTTPResponse) -> String {
    let contentType = answer.headers["content-type"] ?? "no content type"
    let body = answer.body
    if let object = try? JSONSerialization.jsonObject(with: body, options: [.fragmentsAllowed]) {
        if let fields = object as? [String: Any] {
            let entries = fields.keys.sorted().map { "\($0) is \(describeValue(fields[$0] ?? NSNull()))" }
            return "status \(answer.status), \(contentType), JSON object with \(entries.joined(separator: ", "))"
        }
        return "status \(answer.status), \(contentType), JSON \(describeValue(object))"
    }
    guard let text = String(data: body, encoding: .utf8), !text.isEmpty else {
        return "status \(answer.status), \(contentType), \(body.count) bytes, not text"
    }
    let start = String(text.prefix(8)).debugDescription
    return "status \(answer.status), \(contentType), text of \(body.count) bytes, starts \(start)"
}

/// Describes one JSON value without its content: a string by length, first characters and characters outside base64.
private func describeValue(_ value: Any) -> String {
    switch value {
    case let text as String:
        let base64 = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/= \t\r\n")
        let outside = Set(text).filter { !base64.contains($0) }.sorted().prefix(8).map(\.debugDescription)
        let start = String(text.prefix(8)).debugDescription
        return "a string of \(text.count) characters, starts \(start), outside base64 \(outside)"
    case let flag as Bool:
        return "\(flag)"
    default:
        return "\(type(of: value))"
    }
}

/// Runs against the WP-03 testbed when `HERMES_TESTBED_URL` is set (for example `http://127.0.0.1:9119`). CI's testbed
/// job runs it. The testbed keeps an exported bot on its own disk and answers with that path. The probe checks the
/// answer is a path, not archive bytes. It has no import check: import needs bytes the phone cannot get yet.
/// If the server starts answering with bytes, the probe fails on purpose, so the bytes check can return.
/// Without the variable the test passes without doing anything.
@Suite struct ProfileTransferLiveTests {
    @Test(.timeLimit(.minutes(3))) func exportDefaultProfileAnswersWithAServerPath() async throws {
        guard let base = ProcessInfo.processInfo.environment["HERMES_TESTBED_URL"],
            let endpoint = HermesEndpoint(string: base)
        else { return }
        let client = RESTClient(endpoint: endpoint, transport: URLSessionHTTPTransport())
        try await client.passwordLogin(username: "tester", password: "testbed-password")

        let answer = try await client.sendRaw(
            "POST", "/api/profiles/default/export", body: ExportBody(), scoped: false,
            timeout: ProfileArchive.exportTimeout)
        #expect(answer.status == 200)
        #expect(answer.headers["content-type"]?.lowercased().contains("text/html") != true, "a login page is no export")
        do {
            _ = try ProfileArchive.from(answer: answer)
            Issue.record(
                "The export answer carries archive bytes now, so the server changed. Answer: \(shape(of: answer))")
        } catch ProfileTransferError.serverPath(let path) {
            #expect(path.hasPrefix("/"), "the server names the archive by an absolute path on its disk")
        } catch {
            Issue.record(
                "The export answer is neither bytes nor a server path (\(error)). Answer: \(shape(of: answer))")
        }
    }
}
