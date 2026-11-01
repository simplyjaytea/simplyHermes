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

/// Profiles listing JSON helper with ui_meta and revisions.
func botListing(_ profile: String = "ops", revisions: String = "{}", uiMeta: String = "{}") -> String {
    #"""
    {"profiles": [{"name": "\#(profile)", "path": "/p/\#(profile)", "ui_meta": \#(uiMeta),
      "ui_meta_revisions": \#(revisions)}], "bot_mode_protocol": true, "install_id": "I1"}
    """#
}

/// Answers each method from a script of replies. A method's last reply repeats once its script runs out.
/// With `activeProfile` set, each call is scoped the way `GatewayClient` scopes it (`ProfileScope`): a method that
/// takes `profile` and does not name one records the active profile.
actor FakeBotGateway: BotGateway {
    enum Reply: Sendable {
        case json(String)
        case failure(RPCError)
    }

    struct Call: Sendable {
        let method: String
        let params: JSONValue?
    }

    private var scripts: [String: [Reply]]
    private let activeProfile: String?
    private(set) var calls: [Call] = []

    init(_ scripts: [String: [Reply]], activeProfile: String? = nil) {
        self.scripts = scripts
        self.activeProfile = activeProfile
    }

    func call<Value: Decodable & Sendable>(
        _ method: String, params: (any Encodable & Sendable)?, as type: Value.Type
    ) async throws -> Value {
        let encoded = try params.map { try JSONValue(encoding: $0) }
        calls.append(
            Call(method: method, params: ProfileScope.scoped(method: method, params: encoded, profile: activeProfile)))
        guard let script = scripts[method], let reply = script.first else {
            throw RPCError(code: -32601, message: "no reply scripted for \(method)")
        }
        if script.count > 1 { scripts[method] = Array(script.dropFirst()) }
        switch reply {
        case .json(let text): return try JSONDecoder().decode(Value.self, from: Data(text.utf8))
        case .failure(let error): throw error
        }
    }
}
