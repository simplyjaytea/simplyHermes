import Foundation
import Testing

@testable import HermesKit

/// The ASCII text of `count` bytes at `offset`.
private func text(_ data: Data, at offset: Int, count: Int) -> String? {
    String(bytes: data[offset..<offset + count], encoding: .ascii)
}

/// Reads a little-endian unsigned integer of `bytes` bytes at `offset`.
private func littleEndian(_ data: Data, at offset: Int, bytes: Int) -> UInt32 {
    (0..<bytes).reduce(UInt32(0)) { value, index in value | UInt32(data[offset + index]) << (8 * index) }
}

@Suite struct SpeechCodecTests {
    @Test func dataURLRoundTripKeepsMimeTypeAndBytes() {
        let bytes = Data([1, 2, 3, 250])
        let url = DataURL.encode(bytes, mimeType: "audio/webm;codecs=opus")

        #expect(url.hasPrefix("data:audio/webm;codecs=opus;base64,"))
        #expect(DataURL.decode(url) == DataURL.Decoded(mimeType: "audio/webm;codecs=opus", data: bytes))
    }

    @Test func decodeRejectsAnythingThatIsNotABase64DataURL() {
        #expect(DataURL.decode("https://example.com/voice.mp3") == nil)
        #expect(DataURL.decode("data:audio/mpeg,raw-bytes") == nil)
        #expect(DataURL.decode("data:audio/mpeg;base64,!!!") == nil)
    }

    @Test func wavHeaderDescribesMono16BitPCM() throws {
        let samples: [Int16] = [0, 1000, -1000, Int16.max]
        let wav = WAVFile.encode(samples: samples, sampleRate: 16_000)

        #expect(wav.count == 44 + 8)
        #expect(text(wav, at: 0, count: 4) == "RIFF")
        #expect(littleEndian(wav, at: 4, bytes: 4) == 44)
        #expect(text(wav, at: 8, count: 4) == "WAVE")
        #expect(text(wav, at: 12, count: 4) == "fmt ")
        #expect(littleEndian(wav, at: 16, bytes: 4) == 16)
        #expect(littleEndian(wav, at: 20, bytes: 2) == 1)
        #expect(littleEndian(wav, at: 22, bytes: 2) == 1)
        #expect(littleEndian(wav, at: 24, bytes: 4) == 16_000)
        #expect(littleEndian(wav, at: 28, bytes: 4) == 32_000)
        #expect(littleEndian(wav, at: 34, bytes: 2) == 16)
        #expect(text(wav, at: 36, count: 4) == "data")
        #expect(littleEndian(wav, at: 40, bytes: 4) == 8)
        let decoded = stride(from: 44, to: wav.count, by: 2).map { offset in
            Int16(bitPattern: UInt16(littleEndian(wav, at: offset, bytes: 2)))
        }
        #expect(decoded == samples)
    }

    @Test func silenceIsTheFloorAndFullScaleIsZeroDecibels() {
        #expect(AudioLevel.decibels([]) == AudioLevel.silence)
        #expect(AudioLevel.decibels([0, 0, 0]) == AudioLevel.silence)
        #expect(abs(AudioLevel.decibels([Int16.max, -Int16.max, Int16.max, -Int16.max])) < 0.01)
    }

    @Test func halfAmplitudeIsAboutMinusSixDecibels() {
        let half = AudioLevel.decibels(Array(repeating: Int16(16_383), count: 100))
        #expect(abs(half - (-6.02)) < 0.05)
    }

    @Test func unitLevelMapsSixtyDecibelsToZeroOne() {
        #expect(AudioLevel.unit(decibels: 0) == 1)
        #expect(AudioLevel.unit(decibels: -30) == 0.5)
        #expect(AudioLevel.unit(decibels: -60) == 0)
        #expect(AudioLevel.unit(decibels: -120) == 0)
    }
}
