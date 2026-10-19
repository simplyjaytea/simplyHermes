import Foundation
import HermesKit
import Testing

@Suite struct WorkspaceEndpointTests {
    @Test func decodesWorkspacesFromTheServerShape() async throws {
        let http = FakeHTTP()
        http.enqueue(
            200,
            #"""
            {"projects":[],"repos":[{"root":"/opt/hermes","label":"hermes","sessions":1,"last_active":1792298290.8}],
            "default_cwd":"/opt/hermes","home":"/root","scan_enabled":true}
            """#
        )
        let list = try await makeClient(http, profile: "ops").workspaces()

        #expect(list.projects.isEmpty)
        #expect(list.repos.first?.root == "/opt/hermes")
        #expect(list.repos.first?.label == "hermes")
        #expect(list.repos.first?.sessions == 1)
        #expect(list.defaultCwd == "/opt/hermes")
        #expect(list.home == "/root")
        #expect(list.scanEnabled)
        #expect(http.requests.first?.url.absoluteString == "https://hermes.example/api/chat/workspaces?profile=ops")
    }

    @Test func listsAFolderAndSendsThePath() async throws {
        let http = FakeHTTP()
        http.enqueue(
            200,
            #"""
            {"entries":[{"name":"agent","path":"/opt/hermes/agent","isDirectory":true},
            {"name":"README.md","path":"/opt/hermes/README.md","isDirectory":false}]}
            """#
        )
        let list = try await makeClient(http).listFolder("/opt/hermes")

        #expect(list.error == nil)
        #expect(list.entries.map(\.name) == ["agent", "README.md"])
        #expect(list.entries.map(\.isDirectory) == [true, false])
        #expect(http.requests.first?.url.query == "path=/opt/hermes")
    }

    @Test func missingFolderComesBackAsErrorWithNoEntries() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"entries":[],"error":"ENOENT"}"#)
        let list = try await makeClient(http).listFolder("/nope")

        #expect(list.entries.isEmpty)
        #expect(list.error == "ENOENT")
    }

    @Test func readsTextAndBinaryFilesDifferently() async throws {
        let http = FakeHTTP()
        http.enqueue(
            200,
            #"""
            {"binary":false,"byteSize":6,"language":"markdown","mimeType":"text/markdown",
            "path":"/opt/hermes/README.md","text":"Hermes"}
            """#
        )
        http.enqueue(
            200,
            #"""
            {"binary":true,"byteSize":4096,"language":null,"mimeType":"image/png","path":"/opt/hermes/a.png"}
            """#
        )
        let client = makeClient(http)

        let text = try await client.readText("/opt/hermes/README.md")
        #expect(text.text == "Hermes")
        #expect(text.language == "markdown")
        #expect(!text.binary)

        let image = try await client.readText("/opt/hermes/a.png")
        #expect(image.text == nil)
        #expect(image.binary)
        #expect(image.language == nil)
        #expect(image.mimeType == "image/png")
    }

    @Test func downloadsTheBytesOfAFile() async throws {
        let http = FakeHTTP()
        http.enqueue(200, "PNG")
        let data = try await makeClient(http).downloadFile("/opt/hermes/a.png")

        #expect(data == Data("PNG".utf8))
        #expect(http.requests.first?.url.query == "path=/opt/hermes/a.png")
    }

    @Test func skipsAProjectRowThatDoesNotDecode() async throws {
        let http = FakeHTTP()
        http.enqueue(
            200,
            #"""
            {"projects":[{"label":"no root here"},{"root":"/work/app","label":"app"}],"repos":[],
            "default_cwd":"/opt/hermes","home":"/root","scan_enabled":true}
            """#
        )
        let list = try await makeClient(http).workspaces()

        #expect(list.projects.map(\.root) == ["/work/app"])
        #expect(list.repos.isEmpty)
        #expect(list.defaultCwd == "/opt/hermes")
    }
}
