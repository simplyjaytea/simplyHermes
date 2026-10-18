import Foundation

/// The offer shown when the server is back: send the last prompt written offline to Hermes (plan Q44).
public struct SendToHermesOffer: Sendable, Equatable {
    /// The offline chat the prompt comes from.
    public let chatID: String
    /// The prompt's message id in that chat.
    public let messageID: Int
    /// The prompt to send.
    public let prompt: String

    /// Creates an offer.
    public init(chatID: String, messageID: Int, prompt: String) {
        self.chatID = chatID
        self.messageID = messageID
        self.prompt = prompt
    }
}

/// The rules for "Send to Hermes". Only the prompt travels back to the server session, and only when the user taps
/// the offer: the on-device model's replies stay in the offline chat.
public enum SendToHermes {
    /// The offer for an offline chat, or nil when there is none to make.
    ///
    /// There is an offer when the chat is still open, the server is reachable, and the user wrote at least one
    /// prompt in it. The prompt is the last one the user wrote, whether or not the on-device model answered it.
    /// While the server is unreachable, starting up or waiting for the user there is no offer: sending then would
    /// only fail.
    public static func offer(
        chat: OfflineChat?, messages: [OfflineChatMessage], server: ServerReachability
    ) -> SendToHermesOffer? {
        guard server == .reachable, let chat, chat.isOpen else { return nil }
        guard let last = messages.last(where: { $0.chatID == chat.id && $0.role == .user }) else { return nil }
        let prompt = last.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return nil }
        return SendToHermesOffer(chatID: chat.id, messageID: last.id, prompt: prompt)
    }
}
