import Foundation

@testable import HermesKit

/// Parses a JSON literal into a `JSONValue`.
func botJSON(_ text: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

/// Decodes REST bodies the way `RESTClient` does: snake case keys become camel case.
func botRESTDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
}
