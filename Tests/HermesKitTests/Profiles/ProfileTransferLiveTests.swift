import Foundation
import HermesKit
import Testing

/// The export body the contract's ProfileExport takes. The app's client sends the same two fields.
private struct ExportBody: Encodable, Sendable {
    var output = ""
    var extraFiles: [String: String] = [:]
}

/// Runs against the WP-03 testbed when `HERMES_TESTBED_URL` is set (for example `http://127.0.0.1:9119`). CI's testbed
/// job runs it. It exports the testbed's `default` profile and imports the archive under a new name. Without the variable
/// the test passes without doing anything. UNTESTED LIVE until this passes in CI: the export and import answers have no
/// contract schema.
/// Describes an answer for a failure message: its status, its type and the shape of its body. It names JSON keys and a
/// short text preview. It never prints archive bytes.
private func shape(of answer: HTTPResponse) -> String {
    let contentType = answer.headers["content-type"] ?? "no content type"
    let body = answer.body
    if let object = try? JSONSerialization.jsonObject(with: body, options: [.fragmentsAllowed]) {
        if let fields = object as? [String: Any] {
            return "status \(answer.status), \(contentType), JSON object with keys \(fields.keys.sorted())"
        }
        if let text = object as? String {
            return "status \(answer.status), \(contentType), JSON string of \(text.count) characters"
        }
        return "status \(answer.status), \(contentType), other JSON"
    }
    guard let text = String(data: body, encoding: .utf8), !text.isEmpty else {
        return "status \(answer.status), \(contentType), \(body.count) bytes, not text"
    }
    let preview = String(text.prefix(40)).debugDescription
    return "status \(answer.status), \(contentType), text of \(body.count) bytes, starts \(preview)"
}

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
