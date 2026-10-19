import Foundation
import HermesKit
import Testing

@Suite struct SessionExportTests {
    @Test func fileNameUsesTheTitle() {
        #expect(
            SessionExport.fileName(title: "Deploy script: v2?", sessionID: "20261014_032737_07e33f")
                == "hermes-session-Deploy-script-v2.json")
    }

    @Test func fileNameFallsBackToTheIDWithoutATitle() {
        #expect(
            SessionExport.fileName(title: nil, sessionID: "20261014_032737_07e33f")
                == "hermes-session-20261014_032737_07e33f.json")
        #expect(
            SessionExport.fileName(title: " / \\ ", sessionID: "abc") == "hermes-session-abc.json",
            "a title that leaves nothing falls back to the id")
        #expect(SessionExport.fileName(title: "", sessionID: "") == "hermes-session-chat.json")
    }

    @Test func fileNameIsCappedAndKeepsLettersOutsideASCII() {
        let long = String(repeating: "a", count: 90)
        let name = SessionExport.fileName(title: long, sessionID: "x")
        #expect(name == "hermes-session-" + String(repeating: "a", count: 60) + ".json")
        #expect(SessionExport.fileName(title: "Café – notes", sessionID: "x") == "hermes-session-Café-notes.json")
    }

    @Test func jsonCheckAcceptsAnyJSONAndRejectsTheRest() {
        #expect(SessionExport.isJSON(Data(#"{"id":"a","messages":[]}"#.utf8)))
        #expect(SessionExport.isJSON(Data("[]".utf8)))
        #expect(SessionExport.isJSON(Data("42".utf8)))
        #expect(!SessionExport.isJSON(Data("<html>Sign in</html>".utf8)))
        #expect(!SessionExport.isJSON(Data()))
    }
}
