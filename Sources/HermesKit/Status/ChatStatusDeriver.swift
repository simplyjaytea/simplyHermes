import Foundation

/// Derives one chat's status from the facts about it. It is pure: no clock and no I/O, so every rule has a table row.
public enum ChatStatusDeriver {
    /// The status of a chat when the app has no server set up (O6).
    public static let noServer = ChatStatus(pill: .noServer, canSend: false, sendPath: .askUser)

    /// The status of `backend`, given its server connection (for server chats), the network path and the on-device
    /// model. A server chat ignores the on-device model; a local chat ignores the connection and the network.
    public static func derive(
        backend: ChatBackend, phase: ConnectionPhase?, path: NetworkPath, local: LocalModelStatus
    ) -> ChatStatus {
        switch backend {
        case .server:
            serverStatus(phase: phase, path: path)
        case .local:
            localStatus(local)
        }
    }

    // MARK: - Server chats

    private static func serverStatus(phase: ConnectionPhase?, path: NetworkPath) -> ChatStatus {
        // A missing network means the server cannot be reached now, whatever the connection last reported.
        let noNetwork = path == .unsatisfied
        switch phase ?? .idle {
        case .idle, .unlocking, .openingTunnel, .checkingServer, .connecting:
            return noNetwork ? unreachable : connecting
        case .connected:
            return noNetwork ? unreachable : connected
        case .reconnecting:
            return noNetwork ? unreachable : reconnecting
        case .signInRequired:
            return needsAttention(.signIn)
        case .updateRequired:
            return needsAttention(.serverUpdate)
        case .failed(let failure):
            return status(for: failure)
        }
    }

    /// Maps a failed connection attempt onto the pill. Transport and server-side failures keep the chat waiting for the
    /// user's choice; anything the user has to fix names its reason.
    private static func status(for failure: ConnectionTestFailure) -> ChatStatus {
        switch failure {
        case .unreachable, .rateLimited, .server, .ssh, .webSocket:
            unreachable
        case .signInRequired, .wrongCredentials, .missingSecret:
            needsAttention(.signIn)
        case .serverTooOld:
            needsAttention(.serverUpdate)
        case .hostKeyRejected, .hostKeyChanged:
            needsAttention(.hostKey)
        case .notHermes, .invalidForm, .credentialsUnavailable:
            needsAttention(.settings)
        }
    }

    private static let connecting = ChatStatus(pill: .connecting, canSend: true, sendPath: .hold)
    private static let connected = ChatStatus(pill: .connected, canSend: true, sendPath: .server)
    private static let reconnecting = ChatStatus(pill: .reconnecting, canSend: true, sendPath: .hold)
    private static let unreachable = ChatStatus(pill: .unreachable, canSend: true, sendPath: .askUser)
    private static func needsAttention(_ reason: AttentionReason) -> ChatStatus {
        ChatStatus(pill: .needsAttention(reason), canSend: false, sendPath: .askUser)
    }

    // MARK: - Local chats

    private static func localStatus(_ local: LocalModelStatus) -> ChatStatus {
        switch local {
        case .off:
            ChatStatus(pill: .localOff, canSend: false, sendPath: .hold)
        case .noModel, .downloading, .verifying:
            ChatStatus(pill: .localNoModel, canSend: false, sendPath: .hold)
        case .notLoaded(let model):
            // The weights load when the first message is answered, so the model is ready to answer now.
            ChatStatus(pill: .localReady(identity(model)), canSend: true, sendPath: .local(identity(model)))
        case .loading(let model):
            ChatStatus(pill: .localLoading(identity(model)), canSend: true, sendPath: .hold)
        case .ready(let answeredBy):
            ChatStatus(pill: .localReady(answeredBy), canSend: true, sendPath: .local(answeredBy))
        case .failed(let model, let reason):
            ChatStatus(pill: .localFailed(model, reason: reason), canSend: true, sendPath: .hold)
        }
    }

    private static func identity(_ model: OnDeviceModel) -> ModelIdentity {
        .downloaded(id: model.id, displayName: model.displayName)
    }
}
