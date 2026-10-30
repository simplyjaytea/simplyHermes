import Foundation
import HermesKit
import Testing

private func makeEndpoint(_ string: String, headers: [String: String] = [:]) throws -> HermesEndpoint {
    try #require(HermesEndpoint(string: string, headers: headers))
}

// MARK: - Joining paths

@Test func joinKeepsThePrefixOfTheBaseURL() throws {
    let proxied = try makeEndpoint("https://example.com/hermes/")
    #expect(proxied.url(forPath: "/api/ws").absoluteString == "https://example.com/hermes/api/ws")
    #expect(proxied.url(forPath: "api/ws").absoluteString == "https://example.com/hermes/api/ws")

    let direct = try makeEndpoint("https://example.com")
    #expect(direct.url(forPath: "/api/ws").absoluteString == "https://example.com/api/ws")
    #expect(direct.url(forPath: "/").absoluteString == "https://example.com/")
}

@Test func joinAddsTheSlashWhenTheBaseHasNone() throws {
    let nested = try makeEndpoint("https://example.com/a/b")
    #expect(nested.url(forPath: "/api/ws").absoluteString == "https://example.com/a/b/api/ws")
}

@Test func joinNeverDoublesSlashes() throws {
    let proxied = try makeEndpoint("https://example.com/hermes/")
    #expect(proxied.url(forPath: "//api//ws").absoluteString == "https://example.com/hermes/api/ws")
}

@Test func joinKeepsATrailingSlashOnThePath() throws {
    let proxied = try makeEndpoint("https://example.com/hermes")
    #expect(proxied.url(forPath: "/api/sessions/").absoluteString == "https://example.com/hermes/api/sessions/")
    #expect(proxied.url(forPath: "/api/sessions").absoluteString == "https://example.com/hermes/api/sessions")
}

@Test func joinKeepsAnEncodedPrefixAsWritten() throws {
    let spaced = try makeEndpoint("https://example.com/my%20hermes/")
    #expect(spaced.url(forPath: "/api/ws").absoluteString == "https://example.com/my%20hermes/api/ws")
}

@Test func joinKeepsThePortAndIPv6Hosts() throws {
    let local = try makeEndpoint("http://127.0.0.1:8080")
    #expect(local.url(forPath: "/api/ws").absoluteString == "http://127.0.0.1:8080/api/ws")

    let ipv6 = try makeEndpoint("http://[::1]:8080/x/")
    #expect(ipv6.url(forPath: "/api/ws").absoluteString == "http://[::1]:8080/x/api/ws")
}

@Test func joinKeepsTheQueryAsWritten() throws {
    let proxied = try makeEndpoint("https://example.com/hermes/")
    #expect(
        proxied.url(forPath: "/api/sessions?profile=ops&limit=5").absoluteString
            == "https://example.com/hermes/api/sessions?profile=ops&limit=5")
    #expect(
        proxied.url(forPath: "/api/sessions/?limit=5").absoluteString
            == "https://example.com/hermes/api/sessions/?limit=5")
    // Already encoded in the input, so the escape is not doubled.
    #expect(
        proxied.url(forPath: "/api/search?q=a%20b").absoluteString
            == "https://example.com/hermes/api/search?q=a%20b")
}

@Test func joinEncodesRawSegments() throws {
    let proxied = try makeEndpoint("https://example.com/hermes/")
    #expect(
        proxied.url(forPath: "/api/sessions/my session").absoluteString
            == "https://example.com/hermes/api/sessions/my%20session")
    #expect(
        proxied.url(forPath: "/api/sessions/caf\u{E9}").absoluteString
            == "https://example.com/hermes/api/sessions/caf%C3%A9")
    // A literal percent sign is escaped too: pass raw segments, not encoded ones.
    #expect(
        proxied.url(forPath: "/api/sessions/100%").absoluteString
            == "https://example.com/hermes/api/sessions/100%25")
}

// MARK: - WebSocket URLs

@Test func webSocketURLMapsTheScheme() throws {
    let secure = try makeEndpoint("https://example.com:8443/hermes/")
    #expect(secure.webSocketURL(path: "/api/ws").absoluteString == "wss://example.com:8443/hermes/api/ws")

    let plain = try makeEndpoint("HTTP://127.0.0.1:8080")
    #expect(plain.webSocketURL(path: "/api/ws").absoluteString == "ws://127.0.0.1:8080/api/ws")
}

@Test func webSocketURLAddsTheTokenAndTicket() throws {
    let proxied = try makeEndpoint("https://example.com/hermes/")
    #expect(
        proxied.webSocketURL(path: "/api/ws", token: "a b&c").absoluteString
            == "wss://example.com/hermes/api/ws?token=a%20b%26c")
    #expect(
        proxied.webSocketURL(path: "/api/ws", token: "t", ticket: "tk").absoluteString
            == "wss://example.com/hermes/api/ws?token=t&ticket=tk")
    #expect(
        proxied.webSocketURL(path: "/api/ws", ticket: "tk").absoluteString
            == "wss://example.com/hermes/api/ws?ticket=tk")
    // Unreserved characters stay as written. Other characters are escaped.
    #expect(
        proxied.webSocketURL(path: "/api/ws", token: "Az09-._~").absoluteString
            == "wss://example.com/hermes/api/ws?token=Az09-._~")
    #expect(
        proxied.webSocketURL(path: "/api/ws", token: "a+/=").absoluteString
            == "wss://example.com/hermes/api/ws?token=a%2B%2F%3D")
}

@Test func webSocketURLKeepsThePathQueryBeforeTheCredentials() throws {
    let proxied = try makeEndpoint("https://example.com/hermes/")
    #expect(
        proxied.webSocketURL(path: "/api/ws?profile=ops", token: "t").absoluteString
            == "wss://example.com/hermes/api/ws?profile=ops&token=t")
}

// MARK: - Request headers

@Test func requestHeadersAddTheSessionToken() throws {
    let proxied = try makeEndpoint("https://example.com/hermes/", headers: ["Host": "hermes.local"])
    #expect(proxied.requestHeaders() == ["Host": "hermes.local"])
    #expect(
        proxied.requestHeaders(sessionToken: "tok")
            == ["Host": "hermes.local", "X-Hermes-Session-Token": "tok"])
}

// MARK: - Normalized key

@Test func normalizedKeyDedupesSpellingsOfTheSameServer() throws {
    let spellings = [
        "https://example.com/hermes",
        "HTTPS://Example.COM:443/hermes/",
        "https://example.com/hermes//",
        "https://EXAMPLE.com:443/hermes",
    ]
    for spelling in spellings {
        #expect(try makeEndpoint(spelling).normalizedKey == "https://example.com/hermes", "\(spelling)")
    }
    #expect(try makeEndpoint("https://example.com/").normalizedKey == "https://example.com")
    #expect(try makeEndpoint("https://example.com").normalizedKey == "https://example.com")
}

@Test func normalizedKeyRemovesOnlyTheDefaultPort() throws {
    #expect(try makeEndpoint("HTTP://Host:80/").normalizedKey == "http://host")
    #expect(try makeEndpoint("http://Host:443/").normalizedKey == "http://host:443")
    #expect(try makeEndpoint("https://host:80/").normalizedKey == "https://host:80")
    #expect(try makeEndpoint("https://host:8443/").normalizedKey == "https://host:8443")
    #expect(try makeEndpoint("http://[::1]:8080/x/").normalizedKey == "http://[::1]:8080/x")
}

@Test func normalizedKeyIgnoresHeadersAndKeepsTheSchemeAndPathCase() throws {
    let plain = try makeEndpoint("https://example.com/hermes")
    let withHeaders = try makeEndpoint("https://example.com/hermes", headers: ["Host": "other.local"])
    #expect(plain.normalizedKey == withHeaders.normalizedKey)
    // Path case and scheme both change which server or prefix is meant, so they stay in the key.
    #expect(try makeEndpoint("https://example.com/Hermes").normalizedKey != plain.normalizedKey)
    #expect(try makeEndpoint("http://example.com/hermes").normalizedKey != plain.normalizedKey)
}

// MARK: - Validation

@Test func invalidEndpointsAreRejected() {
    let invalid = [
        "ftp://example.com",
        "wss://example.com/hermes",
        "https://",
        "https://example.com/hermes?profile=ops",
        "https://example.com/#top",
        "https://user:pass@example.com",
        "example.com/hermes",
    ]
    for string in invalid {
        #expect(HermesEndpoint(string: string) == nil, "\(string)")
    }
}

// MARK: - Codable

@Test func endpointRoundTripsThroughCodable() throws {
    let endpoint = try makeEndpoint("https://example.com/hermes/", headers: ["Host": "hermes.local"])
    let data = try JSONEncoder().encode(endpoint)
    #expect(try JSONDecoder().decode(HermesEndpoint.self, from: data) == endpoint)
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(object?["baseURL"] as? String == "https://example.com/hermes/")
}

@Test func decodingRejectsAnInvalidEndpoint() {
    let json = Data(#"{"baseURL":"ftp://example.com","headers":{}}"#.utf8)
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(HermesEndpoint.self, from: json) }
}

@Test func decodingDefaultsToNoHeaders() throws {
    let json = Data(#"{"baseURL":"https://example.com"}"#.utf8)
    let endpoint = try JSONDecoder().decode(HermesEndpoint.self, from: json)
    #expect(endpoint.headers.isEmpty)
    #expect(endpoint.url(forPath: "/api/ws").absoluteString == "https://example.com/api/ws")
}

@Suite struct HermesEndpointEncodeOnceTests {
    private let endpoint = HermesEndpoint(string: "http://box:9119/hermes")!

    @Test func rawPercentSequencesRemainLiteral() {
        #expect(
            endpoint.url(forPath: "/api/skills/team%2Fskill").absoluteString
                == "http://box:9119/hermes/api/skills/team%252Fskill")
        #expect(
            endpoint.url(forPath: "/api/skills/my skill").absoluteString
                == "http://box:9119/hermes/api/skills/my%20skill")
    }
}
