import Foundation

/// Where a Telegram or WhatsApp pairing stands, as the app sees it.
public enum MessagingOnboardingPhase: Sendable, Equatable {
    /// Nothing is running.
    case idle
    /// The start request is out. No pairing id yet.
    case starting
    /// The pairing exists. The user links the account, and the screen checks its state until it is linked.
    case waiting(pairingID: String)
    /// The server reports the account as linked. Applying the pairing comes next.
    case linked(pairingID: String)
    /// The apply request is out.
    case applying(pairingID: String)
    /// The pairing was applied.
    case finished
    /// A request failed. The pairing id stays when there is one, so the user can cancel it.
    case failed(pairingID: String?, message: String)
    /// The user cancelled.
    case cancelled
}

/// Something that happened: a tap, or the answer to a request the screen ran.
public enum MessagingOnboardingEvent: Sendable, Equatable {
    /// The user starts a pairing.
    case start
    /// The start request answered with the pairing id.
    case started(pairingID: String)
    /// The start request failed.
    case startFailed(message: String)
    /// A state check answered. `linked` is true once the account is linked.
    case polled(linked: Bool)
    /// A state check failed.
    case pollFailed(message: String)
    /// The user applies the pairing for these user ids.
    case apply(allowedUserIds: [String])
    /// The apply request succeeded.
    case applied
    /// The apply request failed.
    case applyFailed(message: String)
    /// The user cancels.
    case cancel
}

/// A request the screen must run next, and what to do with its answer.
public enum MessagingOnboardingEffect: Sendable, Equatable {
    /// Send the start request, then report ``MessagingOnboardingEvent/started(pairingID:)`` or a failure.
    case start
    /// Wait a little, then check the pairing and report ``MessagingOnboardingEvent/polled(linked:)``.
    case poll(pairingID: String)
    /// Send the apply request for the pairing, then report ``MessagingOnboardingEvent/applied`` or a failure.
    case apply(pairingID: String, allowedUserIds: [String])
    /// Send the cancel request for the pairing.
    case cancel(pairingID: String)
}

/// The pairing state machine for Telegram and WhatsApp onboarding. It is pure: it never sends a request. No screen
/// uses it yet.
/// The screen feeds it events, runs the effect it returns, and feeds the answer back as the next event.
///
/// An event that does not fit the current phase changes nothing and returns no effect. Cancelling while the start is
/// still on its way leaves the phase at ``MessagingOnboardingPhase/cancelled``. When the start answer arrives, the
/// machine returns a cancel effect for the new pairing, so nothing is left running on the server.
public struct MessagingOnboardingMachine: Sendable, Equatable {
    /// The phase now.
    public private(set) var phase: MessagingOnboardingPhase

    /// Creates a machine in the given phase. New screens start idle.
    public init(phase: MessagingOnboardingPhase = .idle) {
        self.phase = phase
    }

    /// The pairing id the machine holds, when there is one.
    public var pairingID: String? {
        switch phase {
        case .idle, .starting, .finished, .cancelled: nil
        case .waiting(let id), .linked(let id), .applying(let id): id
        case .failed(let id, _): id
        }
    }

    /// Applies one event. Returns the request to run next, or nil.
    @discardableResult
    public mutating func handle(_ event: MessagingOnboardingEvent) -> MessagingOnboardingEffect? {
        switch (phase, event) {
        case (.idle, .start), (.finished, .start), (.cancelled, .start):
            phase = .starting
            return .start
        case (.failed(pairingID: nil, message: _), .start):
            phase = .starting
            return .start
        case (.starting, .started(let id)):
            phase = .waiting(pairingID: id)
            return .poll(pairingID: id)
        case (.cancelled, .started(let id)):
            return .cancel(pairingID: id)
        case (.starting, .startFailed(let message)):
            phase = .failed(pairingID: nil, message: message)
            return nil
        case (.waiting(let id), .polled(let linked)):
            if linked {
                phase = .linked(pairingID: id)
                return nil
            }
            return .poll(pairingID: id)
        case (.waiting(let id), .pollFailed(let message)):
            phase = .failed(pairingID: id, message: message)
            return nil
        case (.linked(let id), .apply(let ids)):
            phase = .applying(pairingID: id)
            return .apply(pairingID: id, allowedUserIds: ids)
        case (.applying, .applied):
            phase = .finished
            return nil
        case (.applying(let id), .applyFailed(let message)):
            phase = .failed(pairingID: id, message: message)
            return nil
        case (.starting, .cancel):
            phase = .cancelled
            return nil
        case (.waiting(let id), .cancel), (.linked(let id), .cancel):
            phase = .cancelled
            return .cancel(pairingID: id)
        case (.failed(pairingID: let id?, message: _), .cancel):
            phase = .cancelled
            return .cancel(pairingID: id)
        case (.failed(pairingID: nil, message: _), .cancel):
            phase = .cancelled
            return nil
        default:
            return nil
        }
    }
}
