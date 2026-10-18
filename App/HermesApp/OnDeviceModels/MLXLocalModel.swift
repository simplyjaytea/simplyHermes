import Foundation
import HermesKit

// The MLX backend for downloaded models (plan WP-65c, Q17). Everything MLX sits behind `canImport`, so the app still
// builds, and falls back to the Apple model alone, when the packages are not linked.
//
// `MLXFoundationModels` compiles to an empty module unless the SDK is iOS 27 (`canImport(FoundationModels, _version: 2)`)
// and its package trait is on (the default), so both checks appear here too.
#if canImport(MLXFoundationModels) && canImport(FoundationModels, _version: 2) && canImport(Tokenizers)
    import FoundationModels
    import MLX
    import MLXFoundationModels
    import MLXLLM
    import MLXLMCommon

    /// A downloaded model, answering through `MLXLanguageModel`. Each call opens a new session, so jobs never share
    /// context, the same as the Apple model. The weights load on the first call and stay in memory until the runtime
    /// unloads them.
    @available(iOS 27.0, *)
    struct MLXLocalModel: LocalModelExecutor {
        private let model: OnDeviceModel
        private let languageModel: MLXLanguageModel
        private let memoryGate: OnDeviceMemoryGate

        init(model: OnDeviceModel, folder: URL, memoryGate: OnDeviceMemoryGate) {
            self.model = model
            self.memoryGate = memoryGate
            // The folder holds the files the download manager fetched. The stop tokens come from the catalog, as the
            // MLX LM registry does for the same models.
            let configuration = ModelConfiguration(directory: folder, extraEOSTokens: Set(model.stopTokens))
            languageModel = MLXLanguageModel(
                configuration: configuration,
                weightsLocation: { _ in folder },
                load: { configuration, progress in
                    try await LLMModelFactory.shared.loadContainer(
                        from: NoRemoteDownloads(), using: TransformersTokenizerLoader(), configuration: configuration,
                        progressHandler: progress)
                })
        }

        /// The runtime only hands out this executor on a device that can run it, and the folder was checked by the
        /// selection, so the model is always ready to try.
        var availability: LocalModelAvailability { .available }

        func respond(instructions: String, prompt: String) async throws -> String {
            // A model too big for the memory left is refused before it loads: the selection falls back to Apple. Only
            // a load is checked. Once the model has answered, its weights count against the app, so the gate lets it
            // through instead of refusing it for the room it already takes.
            try await memoryGate.answer(with: model) {
                let session: LanguageModelSession
                if instructions.isEmpty {
                    session = LanguageModelSession(model: languageModel)
                } else {
                    session = LanguageModelSession(model: languageModel) { instructions }
                }
                return try await session.respond(to: prompt).content
            }
        }
    }

    /// The model folders are complete before MLX sees them, so the downloader MLX LM asks for is never used.
    private struct NoRemoteDownloads: MLXLMCommon.Downloader {
        struct Refused: Error {}

        func download(
            id: String, revision: String?, matching patterns: [String], useLatest: Bool,
            progressHandler: @Sendable @escaping (Progress) -> Void
        ) async throws -> URL {
            throw Refused()
        }
    }

    /// Hands the selection an MLX executor for each downloaded model, and unloads them all on request.
    @available(iOS 27.0, *)
    struct MLXModelRuntime: OnDeviceModelRuntime {
        let memoryGate: OnDeviceMemoryGate

        func executor(for model: OnDeviceModel, folder: URL) -> (any LocalModelExecutor)? {
            MLXLocalModel(model: model, folder: folder, memoryGate: memoryGate)
        }

        /// Drops every loaded model from MLX's cache, then frees the buffers MLX kept for reuse. The gate hears of it
        /// first, so the next answer is checked as a load again.
        func unloadAll() async {
            memoryGate.noteUnloaded()
            await MLXLanguageModel.evictAll()
            MLX.Memory.clearCache()
        }
    }
#endif

/// The runtime for downloaded models, or nil where none can run: the Simulator has no Metal GPU for MLX, and a build
/// without the MLX packages has nothing to run. With nil the Apple model always answers. The app targets iOS 27.1, so
/// the `@available` marks above need no `#available` check here.
func makeMLXRuntime(memoryGate: OnDeviceMemoryGate) -> (any OnDeviceModelRuntime)? {
    #if canImport(MLXFoundationModels) && canImport(FoundationModels, _version: 2) && canImport(Tokenizers)
        #if !targetEnvironment(simulator)
            return MLXModelRuntime(memoryGate: memoryGate)
        #else
            return nil
        #endif
    #else
        return nil
    #endif
}
