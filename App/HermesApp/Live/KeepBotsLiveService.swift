import AVFoundation
import HermesUI
import OSLog

/// "Keep bots live": while the switch is on and a bot works, plays silent audio mixed with other
/// apps, which keeps the app (and its WebSocket) running in the background so the Live Activity
/// stays current. Stops with the last running turn. App Store review would reject this; simplyHermes
/// is sideloaded, so it is allowed (plan decision D1).
@MainActor
final class KeepBotsLiveService {
    private var engine: AVAudioEngine?
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.simplyjaytea.simplyhermes", category: "KeepBotsLive")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isEnabled: Bool { defaults.bool(forKey: KeepBotsLiveSetting.key) }
    var isHolding: Bool { engine != nil }

    /// Holds or releases the audio session for the number of turns running now.
    func update(runningTurns: Int) {
        if isEnabled && runningTurns > 0 {
            hold()
        } else {
            release()
        }
    }

    private func hold() {
        guard engine == nil else { return }
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        do {
            try SharedAudioSession.shared.claim(.keepAlive)
            let format = engine.mainMixerNode.outputFormat(forBus: 0)
            guard let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(format.sampleRate))
            else { return }
            silence.frameLength = silence.frameCapacity
            if let channels = silence.floatChannelData {
                for channel in 0..<Int(format.channelCount) {
                    channels[channel].update(repeating: 0, count: Int(silence.frameLength))
                }
            }
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            try engine.start()
            player.scheduleBuffer(silence, at: nil, options: .loops)
            player.play()
            self.engine = engine
            logger.info("Holding the app awake for running bots")
        } catch {
            logger.error("Keep bots live failed: \(error.localizedDescription, privacy: .public)")
            SharedAudioSession.shared.release(.keepAlive)
        }
    }

    private func release() {
        if let engine {
            engine.stop()
            self.engine = nil
            logger.info("Released the app for suspension")
        }
        // Gives the session back even when no engine runs, so a claim left by a hold that failed is dropped too.
        SharedAudioSession.shared.release(.keepAlive)
    }
}
