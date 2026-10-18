#if canImport(UIKit)
    import Foundation
    import HermesKit

    /// The REST client of the active server, once its connection is up (WP-53a).
    @MainActor
    enum ProviderServer {
        static func rest(_ connections: ConnectionsModel) async -> RESTClient? {
            guard let connection = connections.active, let manager = connections.manager else { return nil }
            return await manager.rest(for: connection.id)
        }
    }

    /// What a failed call says on screen. It never shows the request or a secret.
    enum ProviderErrorText {
        static func message(for error: any Error) -> String {
            guard let failure = error as? RESTError else { return "Something went wrong. Try again." }
            switch failure {
            case .unauthorized: return "Sign in again, then retry."
            case .rateLimited: return "The server is busy. Wait a moment, then retry."
            case .http(_, let detail): return detail ?? "The server refused the change."
            case .unexpectedContent: return "The server sent a web page, not an answer. Check the server address."
            case .transport: return "Could not reach the server."
            case .decoding: return "The server sent an answer this version cannot read."
            }
        }
    }

    /// The words shown for a provider key check (`POST /api/providers/validate`).
    enum ProviderKeyCheckText {
        static func text(for check: ProviderCredentialCheck) -> String {
            if check.ok { return "The provider accepted this key." }
            if check.reachable == false { return check.message ?? "Could not reach the provider. You can still save." }
            return check.message ?? "The provider refused this key."
        }
    }

    /// An answer the API contract does not type, shown as JSON text. `limit` cuts long text; nil keeps all of it.
    enum ProviderAnswer {
        static func text(_ value: JSONValue, limit: Int? = nil) -> String {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let json = (try? encoder.encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? ""
            guard let limit, json.count > limit else { return json }
            return String(json.prefix(limit)) + "…"
        }
    }

    /// The reasoning-effort values the pickers offer. The API contract does not list them;
    /// the server has the last word.
    enum ModelDefaultsEffort {
        static let options = ["minimal", "low", "medium", "high", "xhigh"]
    }

    /// Names for the custom endpoint API modes.
    enum ProviderModeLabel {
        static func title(for mode: ProviderAPIMode) -> String {
            switch mode {
            case .chatCompletions: "Chat completions"
            case .codexResponses: "Codex responses"
            case .anthropicMessages: "Anthropic messages"
            }
        }
    }

    extension String {
        /// The text without surrounding spaces and line breaks.
        var providerTrimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

        /// The trimmed text, or nil when nothing is left.
        var providerNonEmpty: String? {
            let text = providerTrimmed
            return text.isEmpty ? nil : text
        }
    }

    /// Sample answers for previews, decoded from JSON with the same key rules as the REST client.
    enum ProviderSamples {
        static let providers: [ModelProviderOptions] =
            decode(
                ModelOptions.self,
                #"""
                {"providers":[
                  {"slug":"openrouter","name":"OpenRouter","authenticated":true,"is_current":true,
                   "models":["example-large","example-small"],"total_models":2},
                  {"slug":"nous","name":"Nous Portal","authenticated":false,"is_current":false,
                   "models":["example-medium"],"total_models":1},
                  {"slug":"lab","name":"Lab endpoint","authenticated":true,"is_current":false,
                   "models":["lab-model"],"total_models":1}
                ]}
                """#
            )?.providers ?? []

        static let modelInfo: ModelInfo? = decode(
            ModelInfo.self, #"{"model":"example-large","provider":"openrouter","effective_context_length":200000}"#)

        static let auxiliary: ModelDefaultsAuxiliary? = decode(
            ModelDefaultsAuxiliary.self,
            #"""
            {"tasks":[
              {"task":"vision","provider":"openrouter","model":"example-small","base_url":""},
              {"task":"title","provider":"auto","model":"","base_url":"","label":"Chat titles",
               "hint":"Short titles","plugin":"chat"}
            ],"main":{"provider":"openrouter","model":"example-large"}}
            """#
        )

        private static func decode<Value: Decodable>(_ type: Value.Type, _ json: String) -> Value? {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try? decoder.decode(type, from: Data(json.utf8))
        }
    }
#endif
