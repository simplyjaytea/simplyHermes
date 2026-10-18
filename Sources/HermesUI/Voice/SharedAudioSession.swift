#if canImport(UIKit)
    import AVFoundation

    /// The app's one audio session. Voice, read aloud and "Keep bots live" all share it, so each one claims it here and
    /// gives it back here. The category follows the claim with the highest precedence. The session is deactivated, so
    /// other apps resume, only when no claim is left. Voice therefore never shuts off a running keep-alive.
    @MainActor
    public final class SharedAudioSession {
        /// What needs the session. A higher case sets the category: the microphone over speech, speech over keep-alive.
        public enum Claim: Int, Sendable {
            /// "Keep bots live" holds the session with silent audio that mixes with other apps.
            case keepAlive = 0
            /// A reply is read aloud. It plays over other apps' audio instead of stopping it.
            case speech = 1
            /// The microphone is recording for dictation or a voice conversation.
            case microphone = 2
        }

        public static let shared = SharedAudioSession()

        private var claims: Set<Claim> = []

        /// Takes the session for `claim` and activates it. Throws when the category or the session cannot be set.
        public func claim(_ claim: Claim) throws {
            let before = top
            claims.insert(claim)
            if let next = top, next != before {
                try configure(next)
            }
            try AVAudioSession.sharedInstance().setActive(true)
        }

        /// Gives the session back for `claim`. Another claim left keeps the session active with its category. When none
        /// is left, the session is deactivated and other apps are told they can resume.
        public func release(_ claim: Claim) {
            let before = top
            claims.remove(claim)
            guard top != before else { return }
            if let next = top {
                try? configure(next)
            } else {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
        }

        private var top: Claim? {
            claims.max { $0.rawValue < $1.rawValue }
        }

        /// Sets the category and mode that `claim` needs. The caller activates the session.
        private func configure(_ claim: Claim) throws {
            let session = AVAudioSession.sharedInstance()
            switch claim {
            case .microphone:
                try session.setCategory(
                    .playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
            case .speech:
                try session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
            case .keepAlive:
                try session.setCategory(.playback, options: [.mixWithOthers])
            }
        }
    }
#endif
