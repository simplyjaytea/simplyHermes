import Foundation

private struct TranscribeBody: Encodable, Sendable {
    var dataUrl: String
    var mimeType: String
}

private struct SpeakBody: Encodable, Sendable {
    var text: String
}

private struct LeaseBody: Encodable, Sendable {
    var lease: String
    var active: Bool
}

/// Answer of `POST /api/audio/transcribe`. An empty `transcript` means the recording had no speech.
public struct SpeechTranscript: Sendable, Equatable, Decodable {
    /// True when the server transcribed the recording.
    public var ok: Bool
    /// The recognized text, trimmed.
    public var transcript: String
    /// The speech provider that answered, when the server names it.
    public var provider: String?
}

/// Answer of `POST /api/audio/speak`: the synthesized text as a base64 `data:` URL.
public struct SpeechAudio: Sendable, Equatable, Decodable {
    /// True when the server synthesized the text.
    public var ok: Bool
    /// `data:<mime>;base64,<payload>`.
    public var dataUrl: String
    /// The audio MIME type, for example `audio/mpeg`.
    public var mimeType: String
    /// The speech provider that answered, when the server names it.
    public var provider: String?

    /// The audio bytes, or nil when ``dataUrl`` is not a base64 data URL.
    public var audio: Data? { DataURL.decode(dataUrl)?.data }
}

/// Answer of the lease calls. The server reports warm-up failures in the body, not as an HTTP error.
private struct LeaseAnswer: Decodable, Sendable {
    var ok: Bool?
}

/// Speech through the Hermes server, the same relay the desktop app uses. Works for every provider the profile has
/// configured, so the app never holds provider keys.
extension RESTClient {
    /// `POST /api/audio/transcribe`. `dataUrl` is a base64 `data:` URL of a recording, up to 25 MB.
    public func transcribe(dataUrl: String, mimeType: String) async throws -> SpeechTranscript {
        try await send("POST", "/api/audio/transcribe", body: TranscribeBody(dataUrl: dataUrl, mimeType: mimeType))
    }

    /// `POST /api/audio/speak`: synthesizes `text` with the profile's text-to-speech provider.
    public func speak(_ text: String) async throws -> SpeechAudio {
        try await send("POST", "/api/audio/speak", body: SpeakBody(text: text))
    }

    /// `POST /api/audio/tts-lease`. `active` true warms the speech engine for `lease`, such as `desktop:read-aloud`.
    /// `active` false releases it, and the server unloads local models once no surface holds a lease.
    public func setSpeechLease(_ lease: String, active: Bool) async throws {
        let _: LeaseAnswer = try await send(
            "POST", "/api/audio/tts-lease", body: LeaseBody(lease: lease, active: active))
    }
}
