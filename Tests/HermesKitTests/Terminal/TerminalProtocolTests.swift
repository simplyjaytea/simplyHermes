import Foundation
import Testing

@testable import HermesKit

@Suite struct TerminalProtocolTests {
    @Test func resizeFrameIsTheWholeEscape() {
        #expect(TerminalProtocol.resizeFrame(columns: 120, rows: 40) == Data("\u{1B}[RESIZE:120;40]".utf8))
    }

    @Test func urlCarriesTicketAttachAndProfile() throws {
        let endpoint = try #require(HermesEndpoint(string: "http://192.168.1.20:9119"))
        let url = TerminalProtocol.url(
            endpoint: endpoint, credential: .ticket("t/1+2"), attach: "tab7", profile: "work")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "ws")
        #expect(components.host == "192.168.1.20")
        #expect(components.port == 9119)
        #expect(components.path == "/api/pty")
        let items = components.queryItems ?? []
        #expect(items.first { $0.name == "attach" }?.value == "tab7")
        #expect(items.first { $0.name == "profile" }?.value == "work")
        #expect(items.first { $0.name == "ticket" }?.value == "t/1+2")
        #expect(items.first { $0.name == "token" } == nil)
    }

    @Test func tokenCredentialUsesTokenQuery() throws {
        let endpoint = try #require(HermesEndpoint(string: "http://127.0.0.1:9119"))
        let url = TerminalProtocol.url(endpoint: endpoint, credential: .token("session-1"), attach: "a", profile: nil)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.first { $0.name == "token" }?.value == "session-1")
        #expect(items.first { $0.name == "ticket" } == nil)
        #expect(items.first { $0.name == "profile" } == nil)
    }

    @Test func noCredentialAndEmptyProfileAddNoQueryItems() throws {
        let endpoint = try #require(HermesEndpoint(string: "https://box.example/hermes"))
        let url = TerminalProtocol.url(endpoint: endpoint, credential: .none, attach: "a", profile: "")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "wss")
        #expect(components.path == "/hermes/api/pty")
        #expect(components.queryItems?.map(\.name) == ["attach"])
    }

    @Test func chatTextFencesTheScreenAndDropsBlankEdges() {
        let lines = ["", "  hello   ", "world  ", "", "   "]
        #expect(TerminalSnapshot.chatText(lines: lines) == "```\n  hello\nworld\n```")
    }

    @Test func chatTextIsNilWhenTheScreenIsBlank() {
        #expect(TerminalSnapshot.chatText(lines: ["", "  "]) == nil)
    }
}
