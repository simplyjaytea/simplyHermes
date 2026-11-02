import Foundation

/// The mode a new chat starts in. The app keeps it as a setting. It changes nothing about a chat that already exists.
public enum ChatMode: String, Sendable, Codable, Equatable {
    /// Answered by the Hermes server.
    case online
    /// Answered by a model on this iPhone.
    case local
}

/// What answers a chat. Fixed when the chat is created (decision 3): a server chat never gets a local reply, and a
/// local chat never reaches the server.
public enum ChatBackend: Sendable, Codable, Hashable {
    /// A chat on a saved server.
    case server(connectionID: UUID, profile: String?, sessionID: String)
    /// A chat that lives only on this iPhone.
    case local(chatID: UUID)
}

/// Whether the phone has a network path, from `NWPathMonitor`. `unknown` until the first report arrives.
public enum NetworkPath: Sendable, Equatable {
    case unknown
    case satisfied
    case unsatisfied
}

/// Which model answers, or would answer. Every Local chat and reply names it, so the user always knows.
public enum ModelIdentity: Sendable, Equatable {
    /// Apple's on-device model.
    case apple
    /// A model downloaded from the catalog.
    case downloaded(id: String, displayName: String)

    /// The name shown to the user.
    public var displayName: String {
        switch self {
        case .apple: "Apple Intelligence"
        case .downloaded(_, let name): name
        }
    }
}

/// Why a local model cannot answer.
public enum LocalModelFailure: Sendable, Equatable {
    /// The on-device runtime is missing: iOS 26 or older, or the Simulator.
    case runtimeUnavailable
    /// The device does not have the memory the model needs. Both values are in bytes.
    case notEnoughMemory(needed: Int64, available: Int64)
    /// The model would not load. The text is for the user.
    case loadError(String)
}

/// The on-device side of a Local chat, as the app observes it.
public enum LocalModelStatus: Sendable, Equatable {
    /// On-device features are turned off.
    case off
    /// No model is usable: none is downloaded, and Apple's model is unavailable.
    case noModel
    /// A model is being downloaded.
    case downloading(progress: Double)
    /// A downloaded model's files are being checked.
    case verifying
    /// A model is chosen, but its weights are not in memory yet.
    case notLoaded(OnDeviceModel)
    /// The weights are loading.
    case loading(OnDeviceModel)
    /// Ready to answer.
    case ready(answeredBy: ModelIdentity)
    /// Cannot answer. The reason is shown.
    case failed(ModelIdentity, reason: LocalModelFailure)
}

/// The status pill's states. The names follow Poppy's state table (UX spec rev 2, §2.2): O1–O6 for online chats and
/// L1–L5 for local chats. The server's name and the model's name come from the screen, not from here.
public enum PillState: Sendable, Equatable {
    /// O1: connected to the server.
    case connected
    /// O2: connecting, or connecting over a new socket.
    case connecting
    /// O3: the connection dropped and is retrying.
    case reconnecting
    /// O4: the server cannot be reached.
    case unreachable
    /// O5: the server answered, but the user has to act first. The reason picks the words and the action.
    case needsAttention(AttentionReason)
    /// O6: the app has no server set up.
    case noServer
    /// L1: the model is ready to answer.
    case localReady(ModelIdentity)
    /// L2: the model is loading into memory.
    case localLoading(ModelIdentity)
    /// L3: no usable on-device model.
    case localNoModel
    /// L4: the model failed, with the reason.
    case localFailed(ModelIdentity, reason: LocalModelFailure)
    /// L5: on-device features are turned off.
    case localOff
}

/// Why an online chat needs the user before it can connect. Each reason has its own words: a changed host key is a
/// security warning, not a sign-in prompt.
public enum AttentionReason: Sendable, Equatable {
    /// Sign in again: no session, wrong credentials or a missing saved secret.
    case signIn
    /// The Hermes server is too old for this app.
    case serverUpdate
    /// The server's SSH host key was rejected or has changed since it was trusted.
    case hostKey
    /// The saved connection is wrong: an invalid form, or the address answers but is not Hermes.
    case settings
}

/// Where a message from a chat goes. Only `.server` reaches Hermes, and only `.local` is answered on this iPhone.
public enum SendPath: Sendable, Equatable {
    /// Sent to the server now.
    case server
    /// Answered on this iPhone by the named model. Only a Local chat gets this.
    case local(ModelIdentity)
    /// Saved and held until the chat can send or answer. Nothing is answered meanwhile.
    case hold
    /// The server cannot be reached. The user decides what happens next. The message is never answered locally.
    case askUser
}

/// What every surface shows for one chat: the pill, whether the composer takes a message, and where it goes.
public struct ChatStatus: Sendable, Equatable {
    /// The pill state.
    public let pill: PillState
    /// Whether the composer accepts a message. The message is saved either way.
    public let canSend: Bool
    /// Where the message goes.
    public let sendPath: SendPath

    /// Creates a status.
    public init(pill: PillState, canSend: Bool, sendPath: SendPath) {
        self.pill = pill
        self.canSend = canSend
        self.sendPath = sendPath
    }
}
