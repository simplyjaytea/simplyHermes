import Foundation

/// Base64 `data:` URLs, the form the server takes recordings in and sends audio back in.
public enum DataURL {
    /// A decoded data URL: its MIME type and its bytes.
    public struct Decoded: Sendable, Equatable {
        /// The MIME type, with any parameters, such as `audio/webm;codecs=opus`.
        public var mimeType: String
        /// The decoded payload.
        public var data: Data
    }

    /// Splits `data:<mime>;base64,<payload>` into its parts. Nil for anything else, including URLs without `;base64`.
    public static func decode(_ url: String) -> Decoded? {
        let scheme = "data:"
        guard url.hasPrefix(scheme), let comma = url.firstIndex(of: ",") else { return nil }
        let header = url[url.index(url.startIndex, offsetBy: scheme.count)..<comma]
        let marker = ";base64"
        guard header.hasSuffix(marker) else { return nil }
        guard let data = Data(base64Encoded: String(url[url.index(after: comma)...])) else { return nil }
        let mimeType = String(header.dropLast(marker.count))
        return Decoded(mimeType: mimeType.isEmpty ? "application/octet-stream" : mimeType, data: data)
    }

    /// `data:<mime>;base64,<payload>` for `data`.
    public static func encode(_ data: Data, mimeType: String) -> String {
        "data:\(mimeType);base64,\(data.base64EncodedString())"
    }
}

/// 16-bit mono PCM in a WAV container, the upload format for dictation and conversation turns.
public enum WAVFile {
    /// `samples` at `sampleRate` hertz as a RIFF/WAVE file.
    public static func encode(samples: [Int16], sampleRate: Int) -> Data {
        let dataSize = samples.count * MemoryLayout<Int16>.size
        var bytes = Data(capacity: 44 + dataSize)
        bytes.append(contentsOf: Array("RIFF".utf8))
        bytes.appendLittleEndian(UInt32(36 + dataSize))
        bytes.append(contentsOf: Array("WAVE".utf8))
        bytes.append(contentsOf: Array("fmt ".utf8))
        bytes.appendLittleEndian(UInt32(16))
        bytes.appendLittleEndian(UInt16(1))
        bytes.appendLittleEndian(UInt16(1))
        bytes.appendLittleEndian(UInt32(sampleRate))
        bytes.appendLittleEndian(UInt32(sampleRate * MemoryLayout<Int16>.size))
        bytes.appendLittleEndian(UInt16(MemoryLayout<Int16>.size))
        bytes.appendLittleEndian(UInt16(16))
        bytes.append(contentsOf: Array("data".utf8))
        bytes.appendLittleEndian(UInt32(dataSize))
        for sample in samples {
            bytes.appendLittleEndian(sample)
        }
        return bytes
    }
}

/// Loudness of PCM samples, for the waveform and the speech detector.
public enum AudioLevel {
    /// The level reported for silence, in dBFS.
    public static let silence = -120.0

    /// Root-mean-square loudness of `samples` in dBFS. 0 is full scale; ``silence`` is the floor.
    public static func decibels(_ samples: [Int16]) -> Double {
        guard !samples.isEmpty else { return silence }
        var sum = 0.0
        for sample in samples {
            let value = Double(sample) / Double(Int16.max)
            sum += value * value
        }
        let rms = (sum / Double(samples.count)).squareRoot()
        guard rms > 0 else { return silence }
        return max(silence, 20 * log10(rms))
    }

    /// Maps a dBFS level to 0...1 across `range` decibels below full scale, for drawing bars.
    public static func unit(decibels: Double, range: Double = 60) -> Double {
        min(1, max(0, (decibels + range) / range))
    }
}

extension Data {
    fileprivate mutating func appendLittleEndian<Value: FixedWidthInteger>(_ value: Value) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
