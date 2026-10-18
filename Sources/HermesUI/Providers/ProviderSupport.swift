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

    /// An answer shown as JSON text, as the server sent it. Used where the answer is not typed (reveal, validate).
    /// `limit` cuts long text; nil keeps all of it.
    enum ProviderAnswer {
        static func text(_ value: JSONValue, limit: Int? = nil) -> String {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let json = (try? encoder.encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? ""
            guard let limit, json.count > limit else { return json }
            return String(json.prefix(limit)) + "…"
        }
    }

    /// The reasoning-effort values the pickers offer. The testbed recorded only "none", so the server has the last word.
    enum ModelDefaultsEffort {
        static let options = ["minimal", "low", "medium", "high", "xhigh"]
    }

    /// Names for the custom endpoint API modes. A value the picker does not know is shown as it is.
    enum ProviderModeLabel {
        static func title(for mode: String) -> String {
            switch mode {
            case ProviderAPIModes.chatCompletions: "Chat completions"
            case ProviderAPIModes.codexResponses: "Codex responses"
            case ProviderAPIModes.anthropicMessages: "Anthropic messages"
            default: mode
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

    /// Sample answers for previews, decoded from JSON with the same key rules as the REST client. They are invented
    /// for previews, not recorded answers.
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
              {"task":"vision","provider":"openrouter","model":"example-small","base_url":"","reasoning_effort":null},
              {"task":"title_generation","provider":"auto","model":"","base_url":"","reasoning_effort":"none"}
            ],"main":{"provider":"openrouter","model":"example-large"}}
            """#
        )

        static let customEndpoints: [ProviderCustomEndpoint] =
            decode(
                ProviderCustomEndpointList.self,
                #"""
                {"endpoints":[
                  {"id":"lab","name":"Lab endpoint","base_url":"http://192.168.1.20:8000/v1","model":"lab-model",
                   "models":["lab-model"],"api_mode":"","discover_models":true,"has_api_key":true,"is_current":true,
                   "source":"providers"},
                  {"id":"home","name":"Home server","base_url":"http://10.0.0.5:11434/v1","model":"example-small",
                   "models":[],"api_mode":"chat_completions","discover_models":false,"has_api_key":false,
                   "is_current":false,"source":"providers"}
                ]}
                """#
            )?.endpoints ?? []

        static let credentialPool: [CredentialPoolProvider] =
            decode(
                CredentialPoolList.self,
                #"""
                {"providers":[{"provider":"openrouter","entries":[
                  {"id":"a1b2c3","index":1,"label":"work","auth_type":"api_key","source":"manual","priority":0,
                   "request_count":12}
                ]}]}
                """#
            )?.providers ?? []

        static let envKeys: [String: ApiKeyEntry] =
            decode(
                [String: ApiKeyEntry].self,
                #"""
                {"OPENROUTER_API_KEY":{"is_set":true,"is_password":true,"provider":"openrouter",
                  "provider_label":"OpenRouter"},
                 "ANTHROPIC_API_KEY":{"is_set":false,"is_password":true,"provider":"anthropic",
                  "provider_label":"Anthropic"}}
                """#
            ) ?? [:]

        private static func decode<Value: Decodable>(_ type: Value.Type, _ json: String) -> Value? {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try? decoder.decode(type, from: Data(json.utf8))
        }
    }
#endif
