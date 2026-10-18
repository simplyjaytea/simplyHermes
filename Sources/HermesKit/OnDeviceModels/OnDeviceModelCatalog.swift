import Foundation

/// One file of a downloadable model: its path in the repository and its exact size at the pinned revision.
public struct OnDeviceModelFile: Sendable, Hashable, Codable {
    /// Path inside the repository, such as `model.safetensors`. Never absolute and never contains `..`.
    public let path: String
    /// Size in bytes. A finished download with another size is damaged and is thrown away.
    public let bytes: Int64

    public init(_ path: String, _ bytes: Int64) {
        self.path = path
        self.bytes = bytes
    }

    /// True for a relative path that stays inside the model folder.
    public var hasSafePath: Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return !path.isEmpty && !path.hasPrefix("/") && !parts.contains { $0.isEmpty || $0 == ".." || $0 == "." }
    }
}

/// A model the app can download and run on the phone (plan WP-65c, Q17 option C).
///
/// Every entry is pinned to one commit of a Hugging Face repository, with the exact file list and sizes, so the size
/// shown before a download is the size that gets downloaded and a repository update cannot change what the app runs.
public struct OnDeviceModel: Sendable, Hashable, Identifiable {
    /// Stable key: the folder name on disk and the saved selection. Not the repository name.
    public let id: String
    /// The name shown in Settings.
    public let displayName: String
    /// One short line on what the model is good for.
    public let summary: String
    /// The Hugging Face repository, such as `mlx-community/<name>`.
    public let repository: String
    /// The commit the file list and sizes were read from.
    public let revision: String
    /// Every file the runtime needs: weights, tokenizer and configuration.
    public let files: [OnDeviceModelFile]
    /// The license name, shown next to the size.
    public let license: String
    /// Tokens that end a reply for this model, passed on to the runtime next to those in the model files.
    public let stopTokens: [String]
    /// True for the model Settings suggests first.
    public let isRecommended: Bool

    public init(
        id: String, displayName: String, summary: String, repository: String, revision: String,
        files: [OnDeviceModelFile], license: String, stopTokens: [String] = [], isRecommended: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.summary = summary
        self.repository = repository
        self.revision = revision
        self.files = files
        self.license = license
        self.stopTokens = stopTokens
        self.isRecommended = isRecommended
    }

    /// The whole download, in bytes. This is the size shown before the download starts.
    public var totalBytes: Int64 { files.reduce(0) { $0 + $1.bytes } }

    /// The weight files only. These are what ends up in memory.
    public var weightBytes: Int64 { files.filter { $0.path.hasSuffix(".safetensors") }.reduce(0) { $0 + $1.bytes } }

    /// A rough memory need while the model answers: the weights, half again for the conversation and working
    /// buffers, and 256 MiB for the runtime. The runtime reports no number; this is an estimate, not a promise.
    public var estimatedMemoryBytes: Int64 { weightBytes + weightBytes / 2 + 256 * 1_048_576 }

    /// Where `file` is downloaded from.
    public func downloadURL(for file: OnDeviceModelFile) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = OnDeviceModelCatalog.host
        components.path = "/\(repository)/resolve/\(revision)/\(file.path)"
        // The components are built from constants and checked paths, so this cannot be nil.
        return components.url ?? URL(fileURLWithPath: "/")
    }
}

/// The models offered in Settings > On-device models.
public struct OnDeviceModelCatalog: Sendable {
    /// Downloads come from here (plan WP-65c: Hugging Face, `mlx-community`).
    public static let host = "huggingface.co"

    public let models: [OnDeviceModel]

    public init(models: [OnDeviceModel]) {
        self.models = models
    }

    public func model(id: String) -> OnDeviceModel? {
        models.first { $0.id == id }
    }

    /// Three 4-bit models from `mlx-community`, small to large. Sizes and commits were read from the Hugging Face API
    /// on 2026-10-18 (`/api/models/<repo>?blobs=true`), keeping the files MLX LM downloads: `*.safetensors`,
    /// `*.json` and `*.jinja`.
    public static let standard = OnDeviceModelCatalog(models: [
        OnDeviceModel(
            id: "gemma-3-1b-4bit",
            displayName: "Gemma 3 1B",
            summary: "Smallest and quickest. Good for short answers.",
            repository: "mlx-community/gemma-3-1b-it-qat-4bit",
            revision: "15fed4eafb456c6fcb2a1165f19ac609670ed14b",
            files: [
                OnDeviceModelFile("added_tokens.json", 35),
                OnDeviceModelFile("config.json", 1105),
                OnDeviceModelFile("model.safetensors", 732_577_304),
                OnDeviceModelFile("model.safetensors.index.json", 50542),
                OnDeviceModelFile("special_tokens_map.json", 662),
                OnDeviceModelFile("tokenizer.json", 33_384_568),
                OnDeviceModelFile("tokenizer_config.json", 1_156_959),
            ],
            license: "Gemma terms of use",
            stopTokens: ["<end_of_turn>"]),
        OnDeviceModel(
            id: "llama-3.2-3b-4bit",
            displayName: "Llama 3.2 3B",
            summary: "A balance of answer quality and speed.",
            repository: "mlx-community/Llama-3.2-3B-Instruct-4bit",
            revision: "7f0dc925e0d0afb0322d96f9255cfddf2ba5636e",
            files: [
                OnDeviceModelFile("config.json", 1122),
                OnDeviceModelFile("model.safetensors", 1_807_496_278),
                OnDeviceModelFile("model.safetensors.index.json", 45720),
                OnDeviceModelFile("special_tokens_map.json", 296),
                OnDeviceModelFile("tokenizer.json", 17_209_920),
                OnDeviceModelFile("tokenizer_config.json", 54558),
            ],
            license: "Llama 3.2 Community License",
            stopTokens: ["<|eot_id|>"]),
        OnDeviceModel(
            id: "qwen3-4b-instruct-4bit",
            displayName: "Qwen3 4B Instruct",
            summary: "The best answers of the three. Needs the most memory.",
            repository: "mlx-community/Qwen3-4B-Instruct-2507-4bit",
            revision: "50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b",
            files: [
                OnDeviceModelFile("added_tokens.json", 707),
                OnDeviceModelFile("chat_template.jinja", 4040),
                OnDeviceModelFile("config.json", 938),
                OnDeviceModelFile("generation_config.json", 238),
                OnDeviceModelFile("model.safetensors", 2_263_022_417),
                OnDeviceModelFile("model.safetensors.index.json", 63964),
                OnDeviceModelFile("special_tokens_map.json", 613),
                OnDeviceModelFile("tokenizer.json", 11_422_654),
                OnDeviceModelFile("tokenizer_config.json", 5440),
                OnDeviceModelFile("vocab.json", 2_776_833),
            ],
            license: "Apache 2.0",
            stopTokens: ["<|im_end|>"],
            isRecommended: true),
    ])
}
