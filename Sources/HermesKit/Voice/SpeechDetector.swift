import Foundation

/// Finds where speech starts and ends in a stream of loudness readings, for hands-free voice input.
///
/// Each reading comes with the length of its frame, so the detector keeps no clock and tests can feed it synthetic
/// audio.
public struct SpeechDetector: Sendable {
    /// What the detector saw.
    public enum Event: Sendable, Equatable {
        /// Speech began.
        case started
        /// Speech ended after enough quiet. `duration` leaves out the trailing quiet.
        case ended(duration: Double)
    }

    /// Thresholds in dBFS and seconds.
    public struct Settings: Sendable, Equatable {
        /// Readings at or above this count as speech.
        public var threshold: Double = -42
        /// Loud time needed before speech counts, so a click does not start an utterance.
        public var minimumSpeech: Double = 0.25
        /// Quiet time that ends an utterance. Shorter pauses stay inside it.
        public var endSilence: Double = 0.9
        /// Longest utterance before it ends on its own.
        public var maximumUtterance: Double = 60

        /// Creates the default thresholds.
        public init() {}
    }

    /// The thresholds in use.
    public let settings: Settings

    private var phase = Phase.quiet(loud: 0)

    private enum Phase: Equatable {
        /// No speech yet. `loud` is the loud time in a row so far.
        case quiet(loud: Double)
        /// Speech in progress. `elapsed` counts from the first loud frame; `quiet` is the trailing quiet time.
        case speaking(elapsed: Double, quiet: Double)
    }

    /// Creates a detector with `settings`.
    public init(settings: Settings = Settings()) {
        self.settings = settings
    }

    /// Feeds one reading: the frame's loudness in dBFS and the frame's length in seconds. Returns an event when speech
    /// starts or ends.
    public mutating func process(decibels: Double, frame: Double) -> Event? {
        let isLoud = decibels >= settings.threshold
        switch phase {
        case .quiet(let loud):
            guard isLoud else {
                phase = .quiet(loud: 0)
                return nil
            }
            let total = loud + frame
            guard total >= settings.minimumSpeech else {
                phase = .quiet(loud: total)
                return nil
            }
            phase = .speaking(elapsed: total, quiet: 0)
            return .started
        case .speaking(let elapsed, let quiet):
            let total = elapsed + frame
            let trailing = isLoud ? 0 : quiet + frame
            guard trailing < settings.endSilence, total < settings.maximumUtterance else {
                phase = .quiet(loud: 0)
                return .ended(duration: total - trailing)
            }
            phase = .speaking(elapsed: total, quiet: trailing)
            return nil
        }
    }

    /// Forgets any speech in progress, for example when the microphone is closed.
    public mutating func reset() {
        phase = .quiet(loud: 0)
    }
}
