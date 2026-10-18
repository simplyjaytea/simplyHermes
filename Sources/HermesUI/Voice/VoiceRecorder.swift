#if canImport(UIKit)
    import AVFoundation
    import HermesKit

    /// Turns the microphone into 16 kHz mono PCM blocks. Voice chat mode turns on echo cancellation, so the microphone
    /// can stay open while a reply plays through the speaker.
    @MainActor
    final class VoiceRecorder {
        private let engine = AVAudioEngine()
        private var continuation: AsyncStream<[Int16]>.Continuation?

        /// Starts capturing and returns the blocks until ``stop()``.
        func start() throws -> AsyncStream<[Int16]> {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard
                let target = AVAudioFormat(
                    commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true),
                let converter = BlockConverter(from: format, to: target)
            else {
                throw VoiceProblem.microphoneUnavailable
            }

            let (stream, continuation) = AsyncStream.makeStream(of: [Int16].self)
            self.continuation = continuation
            input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.tap(converter, continuation))
            engine.prepare()
            try engine.start()
            return stream
        }

        /// Stops capturing, ends the stream and gives the audio session back.
        func stop() {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            continuation?.finish()
            continuation = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }

        /// The tap runs on the audio thread, so it only converts and yields. It must not touch main-actor state.
        private nonisolated static func tap(
            _ converter: BlockConverter, _ continuation: AsyncStream<[Int16]>.Continuation
        ) -> @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void {
            { buffer, _ in
                if let block = converter.convert(buffer) {
                    continuation.yield(block)
                }
            }
        }
    }

    /// Converts microphone buffers to 16 kHz mono Int16. Only the audio thread calls it, one buffer at a time.
    private final class BlockConverter: @unchecked Sendable {
        private let converter: AVAudioConverter
        private let target: AVAudioFormat

        init?(from source: AVAudioFormat, to target: AVAudioFormat) {
            guard let converter = AVAudioConverter(from: source, to: target) else { return nil }
            self.converter = converter
            self.target = target
        }

        func convert(_ buffer: AVAudioPCMBuffer) -> [Int16]? {
            let ratio = target.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
            guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
            let supply = BufferSupply(buffer)
            var conversionError: NSError?
            let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
                guard let next = supply.take() else {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                inputStatus.pointee = .haveData
                return next
            }
            guard status != .error, output.frameLength > 0, let samples = output.int16ChannelData?[0] else {
                return nil
            }
            return Array(UnsafeBufferPointer(start: samples, count: Int(output.frameLength)))
        }
    }

    /// Hands one buffer to the converter. The converter asks for input again, and the second request gets nothing.
    private final class BufferSupply: @unchecked Sendable {
        private var buffer: AVAudioPCMBuffer?

        init(_ buffer: AVAudioPCMBuffer) {
            self.buffer = buffer
        }

        func take() -> AVAudioPCMBuffer? {
            defer { buffer = nil }
            return buffer
        }
    }
#endif
