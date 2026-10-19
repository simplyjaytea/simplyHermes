import Foundation
import HermesKit
import Testing

@Suite struct SessionWorkspaceMoveTests {
    @Test func encodesTheServerKeys() throws {
        let data = try JSONEncoder().encode(
            SessionWorkspaceMoveParams(sessionKey: "stored-1", cwd: "/opt/hermes/agent"))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: String])

        #expect(object == ["session_key": "stored-1", "cwd": "/opt/hermes/agent"])
    }

    @Test func decodesTheResultWithGitRoot() throws {
        let json = #"{"cwd":"/opt/hermes/agent","branch":"d97007c3","git_repo_root":"/opt/hermes"}"#
        let result = try JSONDecoder().decode(SessionWorkspaceMoveResult.self, from: Data(json.utf8))

        #expect(result.cwd == "/opt/hermes/agent")
        #expect(result.branch == "d97007c3")
        #expect(result.gitRepoRoot == "/opt/hermes")
    }

    @Test func noRepoLeavesBranchAndRootEmpty() throws {
        let result = try JSONDecoder().decode(
            SessionWorkspaceMoveResult.self, from: Data(#"{"cwd":"/tmp/scratch"}"#.utf8))

        #expect(result.branch == nil)
        #expect(result.gitRepoRoot == nil)
    }
}
