import Foundation
import Testing

@testable import HermesKit

/// Reads the samples of a canonical 44-byte-header 16 kHz mono WAV file.
private func pcm16Samples(_ wav: Data) -> [Int16] {
    stride(from: 44, to: wav.count, by: 2).map { offset in
        Int16(bitPattern: UInt16(wav[offset]) | UInt16(wav[offset + 1]) << 8)
    }
}

@Suite struct SpeechDetectorTests {
    private let frame = 0.02

    /// Feeds `seconds` of frames at `decibels` and returns the events they produced.
    private func feed(
        _ detector: inout SpeechDetector, _ decibels: Double, seconds: Double
    ) -> [SpeechDetector.Event] {
        (0..<Int((seconds / frame).rounded())).compactMap { _ in
            detector.process(decibels: decibels, frame: frame)
        }
    }

    private func duration(of event: SpeechDetector.Event?) -> Double? {
        guard case .ended(let duration) = event else { return nil }
        return duration
    }

    @Test func utteranceStartsAfterMinimumLoudTimeAndEndsAfterSilence() throws {
        var detector = SpeechDetector()
        var events = feed(&detector, -90, seconds: 0.5)
        events += feed(&detector, -20, seconds: 1.0)
        events += feed(&detector, -90, seconds: 1.0)

        #expect(events.count == 2)
        #expect(events.first == .started)
        let ended = try #require(duration(of: events.last))
        #expect(abs(ended - 1.0) < 0.05)
    }

    @Test func clickShorterThanTheMinimumDoesNotStartAnUtterance() {
        var detector = SpeechDetector()
        var events = feed(&detector, -90, seconds: 0.2)
        events += feed(&detector, -10, seconds: 0.1)
        events += feed(&detector, -90, seconds: 1.0)

        #expect(events.isEmpty)
    }

    @Test func pauseShorterThanTheEndSilenceStaysInsideOneUtterance() throws {
        var detector = SpeechDetector()
        var events = feed(&detector, -20, seconds: 0.5)
        events += feed(&detector, -90, seconds: 0.5)
        events += feed(&detector, -20, seconds: 0.5)
        events += feed(&detector, -90, seconds: 1.0)

        #expect(events.count == 2)
        let ended = try #require(duration(of: events.last))
        #expect(abs(ended - 1.5) < 0.05)
    }

    @Test func longUtteranceEndsOnItsOwnAtTheMaximum() throws {
        var settings = SpeechDetector.Settings()
        settings.maximumUtterance = 2
        var detector = SpeechDetector(settings: settings)
        let events = feed(&detector, -20, seconds: 2.1)

        #expect(events.count == 2)
        let ended = try #require(duration(of: events.last))
        #expect(abs(ended - 2) < 0.05)
    }

    @Test func resetForgetsSpeechInProgress() {
        var detector = SpeechDetector()
        var events = feed(&detector, -20, seconds: 0.5)
        detector.reset()
        events += feed(&detector, -90, seconds: 1.0)

        #expect(events == [.started])
    }

    @Test func syntheticFixtureHoldsOneUtterance() throws {
        let url = FixtureFiles.directory.appendingPathComponent("voice/utterance-synthetic-16k.wav")
        let samples = pcm16Samples(try Data(contentsOf: url))
        let frameSamples = 320
        var detector = SpeechDetector()
        var events: [SpeechDetector.Event] = []
        for start in stride(from: 0, to: samples.count, by: frameSamples) {
            let block = Array(samples[start..<min(start + frameSamples, samples.count)])
            let seconds = Double(block.count) / 16_000
            if let event = detector.process(decibels: AudioLevel.decibels(block), frame: seconds) {
                events.append(event)
            }
        }

        #expect(events.count == 2)
        #expect(events.first == .started)
        let ended = try #require(duration(of: events.last))
        #expect(abs(ended - 2.1) < 0.1)
    }
}
