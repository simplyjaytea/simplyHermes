import Foundation
import HermesKit
import Testing

/// The text a screen shows for a REST failure. `localizedDescription` must read as a sentence, never as the Swift type
/// name and case number.
@Suite struct RESTErrorTextTests {
    @Test func localizedDescriptionIsReadableNotTheTypeName() {
        let error: any Error = RESTError.transport("The Internet connection appears to be offline.")
        #expect(
            error.localizedDescription == "Couldn't reach the server. Check the address and that Hermes is running.")
        #expect(!error.localizedDescription.contains("RESTError"))
    }

    @Test func everyCaseReadsAsASentence() {
        #expect(RESTError.unauthorized.localizedDescription == "The server refused the request. Sign in again.")
        #expect(
            RESTError.rateLimited(retryAfter: 7).localizedDescription == "The server is busy. Try again in a moment.")
        #expect(
            RESTError.unexpectedContent(contentType: "text/html").localizedDescription
                == "The address answered with a web page, not Hermes. Check the address and path.")
        #expect(RESTError.decoding("bad").localizedDescription == "The server sent an answer the app couldn't read.")
    }

    @Test func httpUsesTheServersDetailOrTheStatus() {
        #expect(
            RESTError.http(status: 400, detail: " SKILL.md needs a name.\n").localizedDescription
                == "SKILL.md needs a name.")
        #expect(RESTError.http(status: 500, detail: nil).localizedDescription == "The server answered with status 500.")
        #expect(
            RESTError.http(status: 500, detail: "  ").localizedDescription == "The server answered with status 500.")
    }
}
