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
        let archive = try ProfileArchive.from(answer: answer)
        #expect(!archive.data.isEmpty)

        let name = "wp41-probe-" + String(UUID().uuidString.lowercased().prefix(8))
        let imported = try await client.importProfileArchive(archive.data, name: name)
        #expect(imported.name == nil || imported.name == name, "an import that names a bot names this one")
        #expect(try await client.profiles().contains { $0.name == name }, "the server lists the new bot")
    }
}
