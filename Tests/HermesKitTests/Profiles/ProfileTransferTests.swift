import Foundation
import HermesKit
import Testing

/// Gzip magic bytes followed by a stand-in payload. Export and import both carry this as the archive.
private let gzipBytes = Data([0x1F, 0x8B, 0x08, 0x00]) + Data("profile".utf8)

private func answer(_ body: Data, status: Int = 200) -> HTTPResponse {
    HTTPResponse(status: status, headers: ["content-type": "application/json"], body: body)
}

private func sentBody(_ request: HTTPRequest?) throws -> [String: Any] {
    try #require(request?.body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
}

// Export's answer is not in the contract. These fixtures are the shapes the phone accepts, written from the documented
// request bodies: the same `archive` base64 field that ProfileImport takes, plus a raw file and a server path.
@Suite struct ProfileTransferTests {
    @Test func exportNamesTheProfileInThePathAndSendsTheDocumentedBody() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"archive":"\#(gzipBytes.base64EncodedString())"}"#)
        let client = makeClient(http, profile: "ops")
        let archive = try await client.exportProfileArchive(name: "ops team")
        let request = try #require(http.requests.first)
        #expect(request.method == "POST" && request.url.path == "/api/profiles/ops%20team/export")
        #expect(request.url.query == nil, "the profile is in the path, so the active profile does not scope it")
        let body = try sentBody(request)
        #expect(body["output"] as? String == "")
        #expect((body["extra_files"] as? [String: String])?.isEmpty == true)
        #expect(archive.data == gzipBytes && archive.fileExtension == "tar.gz")
    }

    @Test func exportReadsTheArchiveUnderEachKeyTheAnswerMightUse() throws {
        for key in ["archive", "data", "base64", "content"] {
            let body = Data(#"{"\#(key)":"\#(gzipBytes.base64EncodedString())"}"#.utf8)
            #expect(try ProfileArchive.from(answer: answer(body)).data == gzipBytes, "key \(key)")
        }
        let bare = Data(#""\#(gzipBytes.base64EncodedString())""#.utf8)
        #expect(try ProfileArchive.from(answer: answer(bare)).data == gzipBytes, "a bare JSON string")
    }

    @Test func exportReadsARawArchiveAndNamesItsFormat() throws {
        let gzip = try ProfileArchive.from(
            answer: HTTPResponse(status: 200, headers: ["content-type": "application/gzip"], body: gzipBytes))
        #expect(gzip.data == gzipBytes && gzip.fileExtension == "tar.gz")
        let zipBytes = Data([0x50, 0x4B, 0x03, 0x04]) + Data("profile".utf8)
        let zip = try ProfileArchive.from(
            answer: HTTPResponse(status: 200, headers: ["content-type": "application/zip"], body: zipBytes))
        #expect(zip.data == zipBytes && zip.fileExtension == "zip")
    }

    @Test func exportReadsALongBase64TextAndRefusesOtherText() throws {
        let archive = gzipBytes + Data(repeating: 0x41, count: 120)
        let text = Data(archive.base64EncodedString().utf8)
        let plain = HTTPResponse(status: 200, headers: ["content-type": "text/plain"], body: text)
        #expect(try ProfileArchive.from(answer: plain).data == archive, "a long base64 text is the archive")
        #expect(throws: ProfileTransferError.invalidArchive) {
            try ProfileArchive.from(answer: answer(Data("saved".utf8)))
        }
        #expect(throws: ProfileTransferError.invalidArchive) {
            try ProfileArchive.from(answer: answer(Data("The server ran out of disk space while writing.".utf8)))
        }
    }

    @Test func exportWithOnlyAServerPathSaysThePhoneCannotFetchIt() {
        let body = Data(#"{"ok":true,"path":"/data/hermes/exports/ops.tar.gz"}"#.utf8)
        #expect(throws: ProfileTransferError.serverPath("/data/hermes/exports/ops.tar.gz")) {
            try ProfileArchive.from(answer: answer(body))
        }
    }

    @Test func exportWithoutAnArchiveOrWithBadBase64Fails() {
        #expect(throws: ProfileTransferError.noArchive) { try ProfileArchive.from(answer: answer(Data("{}".utf8))) }
        #expect(throws: ProfileTransferError.noArchive) { try ProfileArchive.from(answer: answer(Data())) }
        #expect(throws: ProfileTransferError.invalidArchive) {
            try ProfileArchive.from(answer: answer(Data(#"{"archive":"!!"}"#.utf8)))
        }
    }

    @Test func theShareFileTakesItsNameFromTheProfileAndItsFormat() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "profile-transfer-tests-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try ProfileArchive(data: gzipBytes).writeTemporaryFile(for: "ops team/2", in: root)
        #expect(url.lastPathComponent == "ops-team-2.tar.gz")
        #expect(try Data(contentsOf: url) == gzipBytes)
        let unnamed = try ProfileArchive(data: Data([0x50, 0x4B, 0x03, 0x04])).writeTemporaryFile(for: "", in: root)
        #expect(unnamed.lastPathComponent == "profile.zip")
    }

    @Test func importSendsTheArchiveAsBase64AndTheNameWhenRenaming() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"ok":true,"name":"ops2"}"#)
        let client = makeClient(http, profile: "ops")
        let result = try await client.importProfileArchive(gzipBytes, name: "ops2")
        #expect(result.name == "ops2")
        let request = try #require(http.requests.first)
        #expect(request.method == "POST" && request.url.path == "/api/profiles/import" && request.url.query == nil)
        let body = try sentBody(request)
        #expect(body["archive"] as? String == gzipBytes.base64EncodedString())
        #expect(body["name"] as? String == "ops2")
    }

    @Test func importWithoutARenameLeavesTheNameOutOfTheBody() async throws {
        let http = FakeHTTP()
        http.enqueue(200, "{}")
        _ = try await makeClient(http).importProfileArchive(gzipBytes)
        let body = try sentBody(http.requests.first)
        #expect(body["name"] == nil && body["archive"] as? String == gzipBytes.base64EncodedString())
    }

    @Test func importAnswersAreReadTolerantly() {
        #expect(ProfileImportResult.from(answer: answer(Data(#"{"ok":true,"name":"ops2"}"#.utf8))).name == "ops2")
        #expect(ProfileImportResult.from(answer: answer(Data("{}".utf8))).name == nil)
        #expect(ProfileImportResult.from(answer: answer(Data("created".utf8))).name == nil)
        #expect(ProfileImportResult.from(answer: answer(Data())).name == nil)
        #expect(ProfileImportResult.from(answer: answer(Data(#"{"name":""}"#.utf8))).name == nil)
    }

    @Test func aRefusedImportShowsTheServersDetail() async throws {
        let http = FakeHTTP()
        http.enqueue(422, #"{"detail":"a profile named ops already exists"}"#)
        let client = makeClient(http)
        let refusal = RESTError.http(status: 422, detail: "a profile named ops already exists")
        await #expect(throws: refusal) {
            try await client.importProfileArchive(gzipBytes)
        }
        #expect(ProfileTransferError.describe(refusal) == "a profile named ops already exists")
        #expect(
            ProfileTransferError.describe(RESTError.http(status: 500, detail: nil))
                == "The server refused the request (HTTP 500).")
        #expect(ProfileTransferError.describe(ConnectionUnavailable(phase: .idle)) == "The server is not reachable.")
    }
}
