import Foundation
import HermesKit
import Testing

// The recorder wraps each answer in `body` and each request in `request` (Fixtures/rest). Decoding is checked against
// these files by type. Values differ from run to run, so tests do not assert sample values.

/// The recorded answer body of a Fixtures/rest file, as the bytes the client receives.
func recordedFixtureAnswer(_ name: String) throws -> String {
    let envelope = try JSONDecoder().decode(JSONValue.self, from: Data(try restFixture(name).utf8))
    let body = try #require(envelope["body"])
    return try #require(String(bytes: try JSONEncoder().encode(body), encoding: .utf8))
}

/// The recorded request of a Fixtures/rest file: method, path, query and body, as the testbed sent it.
func recordedFixtureRequest(_ name: String) throws -> JSONValue {
    let envelope = try JSONDecoder().decode(JSONValue.self, from: Data(try restFixture(name).utf8))
    return try #require(envelope["request"])
}

/// A recorded request body decoded into `T` with the REST client's key rules.
func recordedFixtureBody<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
    let request = try recordedFixtureRequest(name)
    let body = try #require(request["body"])
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(T.self, from: JSONEncoder().encode(body))
}
