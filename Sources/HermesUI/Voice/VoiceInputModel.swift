#if canImport(UIKit)
    import AVFoundation
    import Foundation
    import HermesKit
    import Observation

    /// Problems voice can report. The wording is short and calm, like the rest of the app.
    enum VoiceProblem: LocalizedError {
        case microphoneDenied
        case microphoneUnavailable
        case noServer
        case noSpeech
        case noReply

        var errorDescription: String? {
            switch self {
            case .microphoneDenied: "Allow the microphone in Settings to use voice."
            case .microphoneUnavailable: "The microphone is not available right now."
            case .noServer: "Connect to a Hermes server to use voice."
            case .noSpeech: "No speech was heard."
            case .noReply: "Hermes did not reply in time."
            }
        }
    }

    /// Whether replies are read aloud. The setting stays on this device.
    enum VoicePreferences {
        static let readAloudKey = "voice.readAloud"

        static var readAloud: Bool {
            UserDefaults.standard.bool(forKey: readAloudKey)
        }
    }

    /// Voice for the composer. Dictation records one clip and puts its text in the field. A voice conversation listens,
    /// sends what was said, speaks the reply, and stops talking when the user talks. Speech goes through the server.
    @MainActor
    @Observable
    public final class VoiceInputModel {
        /// What the microphone is doing.
        public enum Mode: Sendable, Equatable {
            /// Off.
            case idle
            /// One clip is being recorded for dictation.
            case dictating
            /// A voice conversation is running.
            case conversation
        }

        /// What the microphone is doing.
        public private(set) var mode = Mode.idle
        /// Where a voice conversation is.
        public private(set) var phase = VoiceConversation.Phase.idle
        /// True while a recording is being transcribed.
        public private(set) var isTranscribing = false
        /// Recent loudness from 0 to 1, newest last, for the waveform.
        public private(set) var levels: [Double] = []
        /// A short problem to show, or nil.
        public private(set) var problem: String?

        /// True while voice is on. The composer then shows its waveform bar instead of the field.
        public var isActive: Bool { mode != .idle }

        /// The status under the waveform.
        public var statusText: String {
            if mode == .dictating { return "Listening" }
            if isTranscribing { return "Transcribing" }
            switch phase {
            case .idle: return ""
            case .listening: return "Listening"
            case .transcribing: return "Transcribing"
            case .waitingForReply: return "Thinking"
            case .speaking: return "Speaking"
            }
        }

        private let server: @Sendable () async -> RESTClient?
        private let insertText: (String) -> Void
        private let sendMessage: (String) -> Void
        private let recorder = VoiceRecorder()
        private let speech = SpeechOutput()
        @ObservationIgnored private var conversation = VoiceConversation()
        @ObservationIgnored private var detector = SpeechDetector()
        @ObservationIgnored private var captureTask: Task<Void, Never>?
        @ObservationIgnored private var transcribeTask: Task<Void, Never>?
        @ObservationIgnored private var speakTask: Task<Void, Never>?
        @ObservationIgnored private var playbackWatch: Task<Void, Never>?
        @ObservationIgnored private var watchdog: Task<Void, Never>?
        /// The last audio before the detector heard speech, so the first word is kept.
        @ObservationIgnored private var recent: [Int16] = []
        /// The whole dictation, or the utterance in progress.
        @ObservationIgnored private var clip: [Int16] = []
        /// The utterance the detector just closed, waiting for transcription.
        @ObservationIgnored private var pendingUtterance: [Int16] = []
        @ObservationIgnored private var isOpen = false
        @ObservationIgnored private var isInUtterance = false

        private static let sampleRate = 16_000
        private static let barCount = 48
        private static let preRollSamples = 4_800
        private static let maximumDictationSamples = 120 * 16_000
        private static let replyTimeout = Duration.seconds(120)

        /// - Parameters:
        ///   - server: The REST client of the connected server, or nil when none is connected.
        ///   - insertText: Puts dictated text into the composer.
        ///   - sendMessage: Sends a spoken message as the next message.
        public init(
            server: @escaping @Sendable () async -> RESTClient?,
            insertText: @escaping (String) -> Void,
            sendMessage: @escaping (String) -> Void
        ) {
            self.server = server
            self.insertText = insertText
            self.sendMessage = sendMessage
        }

        /// Records one clip. ``finish()`` transcribes it and puts the text in the composer.
        public func startDictation() {
            guard mode == .idle else { return }
            begin(.dictating)
            startCapture()
        }

        /// Starts a voice conversation: the user talks, Hermes answers, and the answer is spoken.
        public func startConversation() {
            guard mode == .idle else { return }
            begin(.conversation)
            apply(.start)
            startCapture()
        }

        /// Ends voice input. Dictation transcribes what it recorded. A conversation ends.
        public func finish() {
            guard mode == .dictating else {
                cancel()
                return
            }
            let samples = clip
            endCapture()
            transcribeDictation(samples)
        }

        /// Ends voice input and drops what was said.
        public func cancel() {
            guard mode != .idle else { return }
            if mode == .conversation { apply(.stop) }
            endCapture()
        }

        /// Hermes finished a reply. A conversation speaks it. Otherwise it is read aloud when that setting is on.
        public func replyFinished(_ text: String) {
            switch mode {
            case .conversation where phase == .waitingForReply:
                apply(.reply(text))
            case .idle where VoicePreferences.readAloud:
                speak(text)
            case .conversation, .idle, .dictating:
                break
            }
        }

        private func begin(_ next: Mode) {
            problem = nil
            levels = []
            mode = next
        }

        private func startCapture() {
            captureTask?.cancel()
            captureTask = Task {
                let allowed = await AVAudioApplication.requestRecordPermission()
                guard self.mode != .idle else { return }
                guard allowed else {
                    self.failCapture(.microphoneDenied)
                    return
                }
                let blocks: AsyncStream<[Int16]>
                do {
                    blocks = try self.recorder.start()
                } catch {
                    self.failCapture(.microphoneUnavailable)
                    return
                }
                for await block in blocks {
                    self.receive(block)
                }
            }
        }

        private func failCapture(_ reason: VoiceProblem) {
            guard mode != .idle else { return }
            problem = reason.errorDescription
            cancel()
        }

        private func endCapture() {
            captureTask?.cancel()
            captureTask = nil
            recorder.stop()
            transcribeTask?.cancel()
            speakTask?.cancel()
            playbackWatch?.cancel()
            watchdog?.cancel()
            speech.stop()
            detector.reset()
            conversation = VoiceConversation()
            phase = .idle
            mode = .idle
            clip = []
            recent = []
            pendingUtterance = []
            isOpen = false
            isInUtterance = false
        }

        /// Handles one block of audio: the waveform always, and dictation or the detector while the mic is open.
        private func receive(_ block: [Int16]) {
            levels.append(AudioLevel.unit(decibels: AudioLevel.decibels(block)))
            if levels.count > Self.barCount {
                levels.removeFirst(levels.count - Self.barCount)
            }
            switch mode {
            case .idle:
                return
            case .dictating:
                clip += block
                if clip.count >= Self.maximumDictationSamples { finish() }
            case .conversation:
                guard isOpen else { return }
                let seconds = Double(block.count) / Double(Self.sampleRate)
                switch detector.process(decibels: AudioLevel.decibels(block), frame: seconds) {
                case .started?:
                    isInUtterance = true
                    clip = recent
                    apply(.speechStarted)
                case .ended?:
                    isInUtterance = false
                    pendingUtterance = clip
                    apply(.speechEnded)
                case nil:
                    break
                }
                if isInUtterance {
                    clip += block
                } else {
                    recent += block
                    if recent.count > Self.preRollSamples {
                        recent.removeFirst(recent.count - Self.preRollSamples)
                    }
                }
            }
        }

        private func apply(_ input: VoiceConversation.Input) {
            let effects = conversation.handle(input)
            phase = conversation.phase
            if phase == .waitingForReply {
                startWatchdog()
            } else {
                watchdog?.cancel()
            }
            for effect in effects {
                perform(effect)
            }
        }

        private func perform(_ effect: VoiceConversation.Effect) {
            switch effect {
            case .listen:
                isOpen = true
                detector.reset()
            case .pause:
                isOpen = false
                isInUtterance = false
                detector.reset()
                clip = []
            case .transcribe:
                transcribeConversation(pendingUtterance)
            case .send(let text):
                sendMessage(text)
            case .speak(let text):
                speak(text)
            case .stopSpeaking:
                speakTask?.cancel()
                playbackWatch?.cancel()
                speech.stop()
            case .showError(let message):
                problem = message
            }
        }

        private func transcribeDictation(_ samples: [Int16]) {
            guard !samples.isEmpty else { return }
            isTranscribing = true
            transcribeTask = Task {
                defer { self.isTranscribing = false }
                do {
                    let text = try await self.transcript(of: samples)
                    guard !text.isEmpty else {
                        self.problem = VoiceProblem.noSpeech.errorDescription
                        return
                    }
                    self.insertText(text)
                } catch {
                    self.problem = Self.describe(error)
                }
            }
        }

        private func transcribeConversation(_ samples: [Int16]) {
            isTranscribing = true
            transcribeTask = Task {
                defer { self.isTranscribing = false }
                do {
                    let text = try await self.transcript(of: samples)
                    self.apply(.transcribed(text))
                } catch {
                    self.apply(.failed(Self.describe(error)))
                }
            }
        }

        private func transcript(of samples: [Int16]) async throws -> String {
            guard let rest = await server() else { throw VoiceProblem.noServer }
            let wav = WAVFile.encode(samples: samples, sampleRate: Self.sampleRate)
            let dataUrl = DataURL.encode(wav, mimeType: "audio/wav")
            let answer = try await rest.transcribe(dataUrl: dataUrl, mimeType: "audio/wav")
            return answer.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        /// Speaks with the server's voice, or the system voice when the server cannot. Playback is watched only in a
        /// conversation, where the end of the reply reopens the turn.
        private func speak(_ text: String) {
            speakTask?.cancel()
            playbackWatch?.cancel()
            speakTask = Task {
                let audio = await self.speechAudio(for: text)
                guard !Task.isCancelled else { return }
                if self.mode == .idle {
                    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
                    try? AVAudioSession.sharedInstance().setActive(true)
                }
                if let audio, (try? self.speech.play(audio)) != nil {
                    self.watchPlayback()
                } else {
                    self.speech.speakLocally(text)
                    self.watchPlayback()
                }
            }
        }

        private func speechAudio(for text: String) async -> Data? {
            guard let rest = await server() else { return nil }
            return try? await rest.speak(text).audio
        }

        private func watchPlayback() {
            playbackWatch?.cancel()
            playbackWatch = Task {
                // Speech starts a moment after play() returns, so give it a head start before checking.
                try? await Task.sleep(for: .milliseconds(300))
                while !Task.isCancelled, self.speech.isSpeaking {
                    try? await Task.sleep(for: .milliseconds(150))
                }
                guard !Task.isCancelled, self.phase == .speaking else { return }
                self.apply(.playbackFinished)
            }
        }

        private func startWatchdog() {
            watchdog?.cancel()
            watchdog = Task {
                try? await Task.sleep(for: Self.replyTimeout)
                guard !Task.isCancelled, self.phase == .waitingForReply else { return }
                self.apply(.failed(VoiceProblem.noReply.errorDescription ?? ""))
            }
        }

        private static func describe(_ error: Error) -> String {
            (error as? LocalizedError)?.errorDescription ?? "Voice did not work. Try again."
        }
    }
#endif
