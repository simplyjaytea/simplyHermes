import Foundation
import Testing

@testable import HermesKit

@Suite struct VoiceAPITests {
    @Test func transcribeSendsTheRecordingForTheProfile() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"ok":true,"transcript":"hello there","provider":"openai"}"#)
        let result = try await makeClient(http, profile: "work")
            .transcribe(dataUrl: "data:audio/wav;base64,AAAA", mimeType: "audio/wav")

        #expect(result == SpeechTranscript(ok: true, transcript: "hello there", provider: "openai"))
        let request = try #require(http.requests.first)
        #expect(request.method == "POST")
        #expect(request.url.path == "/api/audio/transcribe")
        let query = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems
        #expect(query?.contains(URLQueryItem(name: "profile", value: "work")) == true)
        let body = try JSONSerialization.jsonObject(with: try #require(request.body)) as? [String: String]
        #expect(body == ["data_url": "data:audio/wav;base64,AAAA", "mime_type": "audio/wav"])
    }

    @Test func emptyTranscriptIsAnAnswerNotAnError() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"ok":true,"transcript":"","provider":null}"#)
        let result = try await makeClient(http).transcribe(dataUrl: "data:audio/wav;base64,AAAA", mimeType: "audio/wav")
        #expect(result.transcript.isEmpty)
    }

    @Test func serverRefusalSurfacesItsDetail() async {
        let http = FakeHTTP()
        http.enqueue(400, #"{"detail":"Audio recording is empty"}"#)
        await #expect(throws: RESTError.http(status: 400, detail: "Audio recording is empty")) {
            try await makeClient(http).transcribe(dataUrl: "data:audio/wav;base64,", mimeType: "audio/wav")
        }
    }

    @Test func speakReturnsTheSynthesizedBytes() async throws {
        let http = FakeHTTP()
        let mp3 = Data([0x49, 0x44, 0x33, 0x04])
        http.enqueue(
            200,
            #"{"ok":true,"data_url":"data:audio/mpeg;base64,\#(mp3.base64EncodedString())","mime_type":"audio/mpeg","provider":"edge"}"#
        )
        let speech = try await makeClient(http).speak("Hello")

        #expect(speech.audio == mp3)
        #expect(speech.mimeType == "audio/mpeg")
        let request = try #require(http.requests.first)
        #expect(request.url.path == "/api/audio/speak")
        let body = try JSONSerialization.jsonObject(with: try #require(request.body)) as? [String: String]
        #expect(body == ["text": "Hello"])
    }

    @Test func speechLeaseNamesTheSurfaceAndState() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"ok":true}"#)
        try await makeClient(http).setSpeechLease("desktop:read-aloud", active: true)

        let request = try #require(http.requests.first)
        #expect(request.url.path == "/api/audio/tts-lease")
        let body = try JSONSerialization.jsonObject(with: try #require(request.body)) as? [String: Any]
        #expect(body?["lease"] as? String == "desktop:read-aloud")
        #expect(body?["active"] as? Bool == true)
    }
}
