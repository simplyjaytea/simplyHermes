import Foundation

/// A room call refused before it was sent (WP-43 spec, sections 1 to 3).
public enum RoomError: Error, Sendable, Equatable {
    case invalidIdentifier(String)
    case invalidDraft([RoomDraft.Problem])
    case invalidName
    case emptyMessage
    case messageTooLarge
    case slashCommand
    /// The approval has no id, so it cannot be answered. It was probably answered already.
    case staleAction
    /// No gateway is connected, so there is nowhere to make the room.
    case noGateway

    /// The words for this refusal.
    public var message: String {
        switch self {
        case .noGateway:
            return "Connect to a gateway first."
        case .invalidIdentifier:
            return "That id is not valid."
        case .invalidDraft(let problems):
            return problems.first?.message ?? "Check the room."
        case .invalidName:
            return "Give the room a name of up to \(RoomDraft.maxNameLength) characters."
        case .emptyMessage:
            return "Type a message first."
        case .messageTooLarge:
            return "That message is too long to send."
        case .slashCommand:
            return "Slash commands are not supported in group chats. "
                + "Open an individual bot chat to use them."
        case .staleAction:
            return "That request is no longer pending."
        }
    }
}

/// Words for a failed room call. The 4xxx codes are the server's hosted-room errors (WP-43 spec, section 0.6).
public enum RoomFailure {
    /// The words a user reads for a room error.
    public static func message(for error: Error) -> String {
        if let roomError = error as? RoomError { return roomError.message }
        guard let rpc = error as? RPCError else { return error.localizedDescription }
        if rpc.data?["reason"]?.stringValue == "authority_conflict" {
            return "This Group Chat is managed by another gateway."
        }
        switch rpc.code {
        case 4123:
            return "The Group Chat worker is not running. Restart the Hermes gateway and try again."
        case 4115:
            return "The room's driver is not running. Try again in a moment."
        case 5116:
            return "This Group Chat is managed by another gateway."
        case 5114:
            return "Stop is still finishing. Try deleting again in a moment."
        default:
            return rpc.message
        }
    }
}

extension Room {
    /// True when the room takes no new messages here: another gateway holds its authority, or a member runs on another
    /// gateway (WP-43 spec, section 5). The log still reads.
    public func isReadOnly(on capabilities: GroupsCapabilitiesResult?) -> Bool {
        readOnlyNote(on: capabilities) != nil
    }

    /// Why the room takes no new messages here, in words for its banner. Nil when it takes them.
    public func readOnlyNote(on capabilities: GroupsCapabilitiesResult?) -> String? {
        if let capabilities, capabilities.authorityGatewayID != authorityGatewayID {
            return "This Group Chat is managed by another gateway. Its history still reads here."
        }
        if members.contains(where: { $0.target?["kind"]?.stringValue == "peer" }) {
            return "A bot in this Group Chat runs on another computer. Open it in Hermes Desktop to keep talking."
        }
        return nil
    }
}
