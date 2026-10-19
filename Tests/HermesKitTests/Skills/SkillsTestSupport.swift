import Foundation
import HermesKit
import Testing

/// The JSON object a request sent, for checking the keys the server's request model expects.
func skillsJSONBody(_ request: HTTPRequest) throws -> [String: Any] {
    let data = try #require(request.body)
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

/// The query items of a request, by name. Repeated names keep the first value.
func skillsQuery(_ request: HTTPRequest) -> [String: String] {
    let items = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
}

/// Serves one recorded answer and returns the decoded value with the request it was sent as.
func skillsRun<Value: Sendable>(
    _ fixture: String, status: Int = 200, profile: String? = "ops", _ call: (RESTClient) async throws -> Value
) async throws -> (Value, HTTPRequest) {
    let http = FakeHTTP()
    http.enqueue(status, try restFixture(fixture))
    let client = makeClient(http, profile: profile)
    let value = try await call(client)
    return (value, try #require(http.requests.first))
}
