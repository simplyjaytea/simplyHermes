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
/// job runs it. It exports the testbed's `default` profile and imports the archive under a new name. Without the variable
/// the test passes without doing anything. UNTESTED LIVE until this passes in CI: the export and import answers have no
/// contract schema.
@Suite struct ProfileTransferLiveTests {
    @Test func exportDefaultProfileThenImportUnderANewName() async throws {
        guard let base = ProcessInfo.processInfo.environment["HERMES_TESTBED_URL"],
            let endpoint = HermesEndpoint(string: base)
        else { return }
        let client = RESTClient(endpoint: endpoint, transport: URLSessionHTTPTransport())
        try await client.passwordLogin(username: "tester", password: "testbed-password")

        let answer = try await client.sendRaw(
            "POST", "/api/profiles/default/export", body: ExportBody(), scoped: false)
        #expect(answer.status == 200)
        #expect(answer.headers["content-type"]?.lowercased().contains("text/html") != true, "a login page is no export")
        let archive: ProfileArchive
        do {
            archive = try ProfileArchive.from(answer: answer)
        } catch {
            Issue.record("The export answer held no archive (\(error)). Answer: \(shape(of: answer))")
            throw error
        }
        #expect(!archive.data.isEmpty)

        let name = "wp41-probe-" + String(UUID().uuidString.lowercased().prefix(8))
        let imported = try await client.importProfileArchive(archive.data, name: name)
        #expect(imported.name == nil || imported.name == name, "an import that names a bot names this one")
        #expect(try await client.profiles().contains { $0.name == name }, "the server lists the new bot")
    }
}
