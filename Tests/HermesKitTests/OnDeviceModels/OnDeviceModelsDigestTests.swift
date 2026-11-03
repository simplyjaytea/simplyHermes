import Foundation
import Testing

@testable import HermesKit

struct OnDeviceModelsDigestTests {
    @Test func matchesTheStandardVector() {
        // FIPS 180-2 test vector for "abc".
        #expect(
            OnDeviceModelDigest.sha256(of: Data("abc".utf8))
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func streamedFileMatchesTheInMemoryDigest() throws {
        let env = TestEnvironment()
        // Spans more than two 1 MiB chunks, so the streaming loop runs several times and ends on a partial chunk.
        let bytes = Data((0..<2_621_441).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        try FileManager.default.createDirectory(at: env.root, withIntermediateDirectories: true)
        let url = env.root.appendingPathComponent("fixture.bin")
        try bytes.write(to: url)
        #expect(try OnDeviceModelDigest.sha256(of: url) == OnDeviceModelDigest.sha256(of: bytes))
    }

    @Test func aFileThatCannotBeReadIsAnError() {
        let missing = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)/model.safetensors")
        #expect(throws: (any Error).self) {
            try OnDeviceModelDigest.sha256(of: missing)
        }
    }
}
