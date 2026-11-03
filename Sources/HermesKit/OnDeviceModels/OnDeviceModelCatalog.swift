import Foundation

/// One file of a downloadable model: its path in the repository, and its exact size and SHA-256 at the pinned revision.
public struct OnDeviceModelFile: Sendable, Hashable, Codable {
    /// Path inside the repository, such as `model.safetensors`. Never absolute and never contains `..`.
    public let path: String
    /// Size in bytes. A finished download with another size is damaged and is thrown away.
    public let bytes: Int64
    /// Lowercase hex SHA-256 of the file. A download with another digest is damaged and is thrown away before MLX
    /// reads it. Pinned from the Hugging Face LFS oid for LFS files, and from the file at the pinned commit otherwise.
    public let sha256: String

    public init(_ path: String, _ bytes: Int64, sha256: String) {
        self.path = path
        self.bytes = bytes
        self.sha256 = sha256
    }

    /// True for a relative path that stays inside the model folder.
    public var hasSafePath: Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return !path.isEmpty && !path.hasPrefix("/") && !parts.contains { $0.isEmpty || $0 == ".." || $0 == "." }
    }

    /// True for a digest written as 64 lowercase hex digits.
    public var hasValidDigest: Bool {
        sha256.count == 64 && sha256.allSatisfy { $0.isHexDigit && !$0.isUppercase }
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
                OnDeviceModelFile(
                    "added_tokens.json", 35, sha256: "50b2f405ba56a26d4913fd772089992252d7f942123cc0a034d96424221ba946"),
                OnDeviceModelFile(
                    "config.json", 1105, sha256: "eb080baebedaa32151a71988721a64f0be067fc6cd7e20ca16ba11231f822533"),
                OnDeviceModelFile(
                    "model.safetensors", 732_577_304,
                    sha256: "b6010f6b03a83f973ca8708eb5784d5b0f80c0e7e9143dbb4c95d0eefe39c837"),
                OnDeviceModelFile(
                    "model.safetensors.index.json", 50542,
                    sha256: "b479eca1f14de16218fc5f45aa270d008944cd3f261f78e90f9b718c8857faef"),
                OnDeviceModelFile(
                    "special_tokens_map.json", 662,
                    sha256: "2f7b0adf4fb469770bb1490e3e35df87b1dc578246c5e7e6fc76ecf33213a397"),
                OnDeviceModelFile(
                    "tokenizer.json", 33_384_568,
                    sha256: "4667f2089529e8e7657cfb6d1c19910ae71ff5f28aa7ab2ff2763330affad795"),
                OnDeviceModelFile(
                    "tokenizer_config.json", 1_156_959,
                    sha256: "be9d72bdf5021aa82d67c3cc60cb0f8ddcc759d4d3f05eb129b9fcc345fc94b7"),
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
                OnDeviceModelFile(
                    "config.json", 1122, sha256: "c546925585e48f43890d9dc5150df4fec73dd3780d92961c5ace451934cc4cd6"),
                OnDeviceModelFile(
                    "model.safetensors", 1_807_496_278,
                    sha256: "d75e1ee0ea653cc5b76191ec934c7c0d568e94d4e47846619f1f4bc715b7b265"),
                OnDeviceModelFile(
                    "model.safetensors.index.json", 45720,
                    sha256: "2ef31fa0b9dcda01f87835851d5e1d5a39ab6258ae618af6ea864c3747e556e4"),
                OnDeviceModelFile(
                    "special_tokens_map.json", 296,
                    sha256: "6f38c73729248f6c127296386e3cdde96e254636cc58b4169d3fd32328d9a8ec"),
                OnDeviceModelFile(
                    "tokenizer.json", 17_209_920,
                    sha256: "6b9e4e7fb171f92fd137b777cc2714bf87d11576700a1dcd7a399e7bbe39537b"),
                OnDeviceModelFile(
                    "tokenizer_config.json", 54558,
                    sha256: "022d5ae3df4737998ab97d8f31ac2bcb4c06dd8ebe5a8aba2b4aceef1e5ea7d3"),
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
                OnDeviceModelFile(
                    "added_tokens.json", 707, sha256: "c0284b582e14987fbd3d5a2cb2bd139084371ed9acbae488829a1c900833c680"
                ),
                OnDeviceModelFile(
                    "chat_template.jinja", 4040,
                    sha256: "40c21f34cf67d8c760ef72f8ad3ae5afad514299d4b06e91dd9a8d705af7b541"),
                OnDeviceModelFile(
                    "config.json", 938, sha256: "574349e5a343236546fda55e4744a76e181f534182d7dc60ff1bad7e7a502849"),
                OnDeviceModelFile(
                    "generation_config.json", 238,
                    sha256: "835fffe355c9438e7a25be099b3fccaa98350b83451f9fd2d99512e74f1ade48"),
                OnDeviceModelFile(
                    "model.safetensors", 2_263_022_417,
                    sha256: "2a73c6c248601ab904e035548abd8e6abb65ea27dcb5f342fb0a8910eb44173f"),
                OnDeviceModelFile(
                    "model.safetensors.index.json", 63964,
                    sha256: "388d811b8b7c2608dd04cce1bcb04a8bf715d19b42790894e6d3427ff429a777"),
                OnDeviceModelFile(
                    "special_tokens_map.json", 613,
                    sha256: "76862e765266b85aa9459767e33cbaf13970f327a0e88d1c65846c2ddd3a1ecd"),
                OnDeviceModelFile(
                    "tokenizer.json", 11_422_654,
                    sha256: "aeb13307a71acd8fe81861d94ad54ab689df773318809eed3cbe794b4492dae4"),
                OnDeviceModelFile(
                    "tokenizer_config.json", 5440,
                    sha256: "4397cc477eb6d79715ccd2000accd6b3531928f30029665832fa1b255f24d2b9"),
                OnDeviceModelFile(
                    "vocab.json", 2_776_833, sha256: "ca10d7e9fb3ed18575dd1e277a2579c16d108e32f27439684afa0e10b1440910"),
            ],
            license: "Apache 2.0",
            stopTokens: ["<|im_end|>"],
            isRecommended: true),
    ])
}
