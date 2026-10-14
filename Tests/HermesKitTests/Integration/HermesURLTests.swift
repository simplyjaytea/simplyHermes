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
