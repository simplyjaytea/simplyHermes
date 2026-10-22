import Foundation

/// The turn-taking of a voice conversation: listen, send what was said, speak the reply, and let the user interrupt
/// the speech. Pure, so the flow is testable without audio hardware.
public struct VoiceConversation: Sendable, Equatable {
    /// Where the conversation is.
    public enum Phase: Sendable, Equatable {
        /// Not running.
        case idle
        /// Listening for the user. The microphone is open.
        case listening
        /// The user's utterance is being transcribed. The microphone is closed.
        case transcribing
        /// The text was sent and the reply has not come yet. The microphone is closed.
        case waitingForReply
        /// Speaking a reply. The microphone stays open so the user can interrupt.
        case speaking
    }

    /// Something that happened: a user action, a detector event or a server answer.
    public enum Input: Sendable, Equatable {
        /// The user turns the conversation on.
        case start
        /// The user turns the conversation off.
        case stop
        /// The detector heard speech.
        case speechStarted
        /// The detector heard the end of an utterance.
        case speechEnded
        /// The utterance was transcribed. Empty means nothing was said.
        case transcribed(String)
        /// The assistant's reply is ready to speak.
        case reply(String)
        /// The speech of the reply finished.
        case playbackFinished
        /// A request failed. The conversation keeps going.
        case failed(String)
    }

    /// What the app should do in response.
    public enum Effect: Sendable, Equatable {
        /// Open the microphone for an utterance.
        case listen
        /// Close the microphone and drop any utterance in progress.
        case pause
        /// Transcribe the utterance that was just recorded.
        case transcribe
        /// Send `text` as the next message.
        case send(String)
        /// Speak `text`.
        case speak(String)
        /// Stop the speech in progress.
        case stopSpeaking
        /// Show `message` without ending the conversation.
        case showError(String)
    }

    /// Where the conversation is now.
    public private(set) var phase = Phase.idle

    /// Creates a conversation that is not running.
    public init() {}

    /// Applies `input` and returns what the app should do. Inputs that do not fit the current phase change nothing.
    public mutating func handle(_ input: Input) -> [Effect] {
        if input == .stop {
            guard phase != .idle else { return [] }
            phase = .idle
            return [.pause, .stopSpeaking]
        }
        switch (phase, input) {
        case (.idle, .start):
            phase = .listening
            return [.listen]
        case (.listening, .speechEnded):
            phase = .transcribing
            return [.pause, .transcribe]
        case (.speaking, .speechStarted):
            phase = .listening
            return [.stopSpeaking]
        case (.transcribing, .transcribed(let text)):
            let spoken = Self.clean(text)
            guard !spoken.isEmpty else {
                phase = .listening
                return [.listen]
            }
            phase = .waitingForReply
            return [.send(spoken)]
        case (.listening, .reply(let text)), (.speaking, .reply(let text)), (.waitingForReply, .reply(let text)):
            return answer(text)
        case (.speaking, .playbackFinished):
            phase = .listening
            return []
        case (.transcribing, .failed(let message)), (.waitingForReply, .failed(let message)):
            phase = .listening
            return [.showError(message), .listen]
        case (.speaking, .failed(let message)), (.listening, .failed(let message)):
            phase = .listening
            return [.showError(message)]
        default:
            return []
        }
    }

    /// Speaks a reply. The microphone opens again when the request had closed it. An empty reply has nothing to say.
    private mutating func answer(_ text: String) -> [Effect] {
        let spoken = Self.clean(text)
        switch phase {
        case .waitingForReply:
            guard !spoken.isEmpty else {
                phase = .listening
                return [.listen]
            }
            phase = .speaking
            return [.listen, .speak(spoken)]
        case .speaking where !spoken.isEmpty:
            return [.stopSpeaking, .speak(spoken)]
        case .listening where !spoken.isEmpty:
            phase = .speaking
            return [.speak(spoken)]
        default:
            return []
        }
    }

    private static func clean(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
