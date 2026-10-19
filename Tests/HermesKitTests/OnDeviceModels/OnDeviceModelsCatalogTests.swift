import Foundation
import Testing

@testable import HermesKit

struct OnDeviceModelsCatalogTests {
    private let models = OnDeviceModelCatalog.standard.models

    @Test func catalogOffersThreeModelsWithUniqueIDs() {
        #expect(models.count == 3)
        #expect(Set(models.map(\.id)).count == models.count)
        #expect(Set(models.map(\.repository)).count == models.count)
    }

    @Test func everyEntryIsPinnedToACommitOfAnMLXCommunityRepository() {
        for model in models {
            #expect(model.repository.hasPrefix("mlx-community/"), "\(model.id)")
            #expect(model.revision.count == 40, "\(model.id)")
            #expect(model.revision.allSatisfy { $0.isHexDigit && !$0.isUppercase }, "\(model.id)")
            #expect(!model.displayName.isEmpty && !model.summary.isEmpty && !model.license.isEmpty)
        }
    }

    @Test func everyEntryListsTheFilesTheRuntimeNeeds() {
        for model in models {
            let paths = model.files.map(\.path)
            #expect(Set(paths).count == paths.count, "\(model.id) lists a file twice")
            #expect(model.files.allSatisfy { $0.hasSafePath && $0.bytes > 0 }, "\(model.id)")
            #expect(paths.contains("config.json"), "\(model.id)")
            #expect(paths.contains("tokenizer.json"), "\(model.id)")
            #expect(paths.contains { $0.hasSuffix(".safetensors") }, "\(model.id)")
            // MLX LM downloads *.safetensors, *.json and *.jinja and nothing else.
            let wanted = [".safetensors", ".json", ".jinja"]
            #expect(paths.allSatisfy { path in wanted.contains { path.hasSuffix($0) } }, "\(model.id)")
        }
    }

    @Test func sizesAddUpToTheValuesRead() throws {
        let recommended = try #require(models.first { $0.isRecommended })
        #expect(recommended.totalBytes == 2_277_297_844)
        #expect(recommended.weightBytes == 2_263_022_417)
        let small = try #require(OnDeviceModelCatalog.standard.model(id: "gemma-3-1b-4bit"))
        #expect(small.totalBytes == 767_171_175)
        let middle = try #require(OnDeviceModelCatalog.standard.model(id: "llama-3.2-3b-4bit"))
        #expect(middle.totalBytes == 1_824_807_894)
        #expect(small.totalBytes < middle.totalBytes && middle.totalBytes < recommended.totalBytes)
    }

    @Test func memoryEstimateIsHigherThanTheWeights() {
        for model in models {
            #expect(model.estimatedMemoryBytes > model.weightBytes)
            #expect(model.weightBytes < model.totalBytes)
        }
        // Weights 100, half again 50, plus 256 MiB.
        let probe = OnDeviceModel(
            id: "p", displayName: "P", summary: "P", repository: "x/p", revision: "r",
            files: [OnDeviceModelFile("w.safetensors", 100), OnDeviceModelFile("c.json", 7)], license: "L")
        #expect(probe.estimatedMemoryBytes == 150 + 256 * 1_048_576)
    }

    @Test func exactlyOneModelIsRecommended() {
        #expect(models.filter(\.isRecommended).count == 1)
    }

    @Test func downloadURLPointsAtThePinnedRevision() throws {
        let model = try #require(OnDeviceModelCatalog.standard.model(id: "qwen3-4b-instruct-4bit"))
        let file = try #require(model.files.first { $0.path == "model.safetensors" })
        #expect(
            model.downloadURL(for: file).absoluteString
                == "https://huggingface.co/mlx-community/Qwen3-4B-Instruct-2507-4bit/resolve/"
                + "50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b/model.safetensors")
    }

    @Test func stopTokensArePassedForEachFamily() throws {
        #expect(OnDeviceModelCatalog.standard.model(id: "gemma-3-1b-4bit")?.stopTokens == ["<end_of_turn>"])
        #expect(OnDeviceModelCatalog.standard.model(id: "llama-3.2-3b-4bit")?.stopTokens == ["<|eot_id|>"])
        #expect(OnDeviceModelCatalog.standard.model(id: "qwen3-4b-instruct-4bit")?.stopTokens == ["<|im_end|>"])
    }

    @Test func lookupFindsModelsByID() {
        #expect(OnDeviceModelCatalog.standard.model(id: "llama-3.2-3b-4bit")?.displayName == "Llama 3.2 3B")
        #expect(OnDeviceModelCatalog.standard.model(id: "nope") == nil)
    }

    @Test func unsafeFilePathsAreRejected() {
        for path in ["", "/etc/passwd", "../x", "a/../b", "a//b", "a/./b", "dir/"] {
            #expect(!OnDeviceModelFile(path, 1).hasSafePath, "\(path)")
        }
        #expect(OnDeviceModelFile("sub/dir/file.json", 1).hasSafePath)
    }
}
