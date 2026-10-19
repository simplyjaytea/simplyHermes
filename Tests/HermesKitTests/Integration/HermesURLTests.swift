import Foundation
import HermesKit
import Testing

@Test func chatURLRoundTrips() {
    let url = HermesURL.chat("backup-42")
    #expect(url.absoluteString == "simplyhermes://chat/backup-42")
    #expect(HermesURL.chatID(from: url) == "backup-42")
}

@Test func otherURLsHaveNoChatID() throws {
    #expect(HermesURL.chatID(from: try #require(URL(string: "simplyhermes://chat"))) == nil)
    #expect(HermesURL.chatID(from: try #require(URL(string: "simplyhermes://settings/x"))) == nil)
    #expect(HermesURL.chatID(from: try #require(URL(string: "https://chat/x"))) == nil)
}

@Test func sessionURLRoundTrips() throws {
    let reference = SessionReference(profile: "ops", sessionID: "20261014_032737_07e33f")
    let url = HermesURL.session(reference)
    #expect(url.absoluteString == "simplyhermes://session/ops/20261014_032737_07e33f")
    #expect(HermesURL.sessionReference(from: url) == reference)
    #expect(HermesURL.chatID(from: url) == nil, "the session route is not the chat route")
    #expect(HermesURL.sessionReference(from: HermesURL.chat("backup-42")) == nil)
}

@Test func otherURLsHaveNoSessionReference() throws {
    func reference(_ text: String) throws -> SessionReference? {
        HermesURL.sessionReference(from: try #require(URL(string: text)))
    }
    #expect(try reference("simplyhermes://session/ops") == nil, "no session id")
    #expect(try reference("simplyhermes://session/ops/abc/extra") == nil, "too many parts")
    #expect(try reference("simplyhermes://session/o%20ps/abc") == nil, "a name outside the grammar")
    #expect(try reference("https://session/ops/abc") == nil, "another scheme")
    #expect(try reference("simplyhermes://settings/ops/abc") == nil, "another route")
    #expect(try reference("simplyhermes://session/ops/abc")?.sessionID == "abc")
}
