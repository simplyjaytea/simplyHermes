#if canImport(Tokenizers)
    import Foundation
    import MLXLMCommon
    import Tokenizers

    // MLX LM and swift-transformers each define `Tokenizer` and `TokenizerError`, so every name here is qualified.

    /// Loads the tokenizer of a downloaded model from its folder with swift-transformers, and adapts it to MLX LM.
    ///
    /// This is what the `MLXHuggingFace` macros expand to, written out by hand. The macros also bring in the Hugging
    /// Face downloader, which this app replaces with its own download manager (WP-65c), so they stay out.
    struct TransformersTokenizerLoader: MLXLMCommon.TokenizerLoader {
        func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
            let upstream = try await Tokenizers.AutoTokenizer.from(modelFolder: directory)
            return TransformersTokenizer(upstream)
        }
    }

    struct TransformersTokenizer: MLXLMCommon.Tokenizer {
        private let upstream: any Tokenizers.Tokenizer

        init(_ upstream: any Tokenizers.Tokenizer) {
            self.upstream = upstream
        }

        func encode(text: String, addSpecialTokens: Bool) -> [Int] {
            upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
        }

        // swift-transformers calls the label `tokens`, MLX LM calls it `tokenIds`.
        func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
            upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
        }

        func convertTokenToId(_ token: String) -> Int? {
            upstream.convertTokenToId(token)
        }

        func convertIdToToken(_ id: Int) -> String? {
            upstream.convertIdToToken(id)
        }

        var bosToken: String? { upstream.bosToken }
        var eosToken: String? { upstream.eosToken }
        var unknownToken: String? { upstream.unknownToken }

        func applyChatTemplate(
            messages: [[String: any Sendable]],
            tools: [[String: any Sendable]]?,
            additionalContext: [String: any Sendable]?
        ) throws -> [Int] {
            do {
                return try upstream.applyChatTemplate(
                    messages: messages, tools: tools, additionalContext: additionalContext)
            } catch Tokenizers.TokenizerError.missingChatTemplate {
                throw MLXLMCommon.TokenizerError.missingChatTemplate
            }
        }
    }
#endif
