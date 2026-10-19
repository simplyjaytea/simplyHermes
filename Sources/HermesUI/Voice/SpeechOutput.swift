#if canImport(UIKit)
    import AVFoundation

    /// Plays speech: the server's audio when it has it, the system voice when it does not.
    @MainActor
    final class SpeechOutput {
        private var player: AVAudioPlayer?
        private let systemVoice = AVSpeechSynthesizer()

        /// True while audio or the system voice is still speaking.
        var isSpeaking: Bool { player?.isPlaying == true || systemVoice.isSpeaking }

        /// Plays encoded audio from the server, such as MP3 or WAV.
        func play(_ audio: Data) throws {
            stop()
            let player = try AVAudioPlayer(data: audio)
            player.prepareToPlay()
            player.play()
            self.player = player
        }

        /// Speaks `text` with the system voice, for when the server cannot synthesize it.
        func speakLocally(_ text: String) {
            stop()
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
            systemVoice.speak(utterance)
        }

        /// Stops whatever is playing at once.
        func stop() {
            player?.stop()
            player = nil
            systemVoice.stopSpeaking(at: .immediate)
        }
    }
#endif
