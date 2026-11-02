import Foundation

/// The colour family of a pill. The app maps each to an ink token, which is AA-checked in every preset.
public enum PillInk: Sendable, Equatable {
    /// Connected to the server.
    case online
    /// Working or waiting on something the user can wait out.
    case warning
    /// The chat cannot send or answer until something changes.
    case problem
    /// Nothing is configured or the feature is off.
    case neutral
    /// A Local chat whose model is ready.
    case local
}

/// The words, symbol, ink and announcements for each pill state (UX spec §2.2, states O1–O6 and L1–L5). Pure: the
/// server's name and the model's name come in as arguments, so every state has a table row.
public enum PillPresentation {
    /// The short title in the header capsule.
    public static func shortTitle(_ pill: PillState, serverName: String) -> String {
        switch pill {
        case .connected: "Online"
        case .connecting, .reconnecting: pill == .connecting ? "Connecting…" : "Reconnecting…"
        case .unreachable: "Can't reach"
        case .needsAttention(let reason): attentionShort(reason)
        case .noServer: "Set up"
        case .localReady(let model): model.displayName
        case .localLoading(let model): "\(model.displayName)…"
        case .localNoModel: "No model"
        case .localFailed: "Load failed"
        case .localOff: "Off"
        }
    }

    /// The full title, used where there is room: the server's name or the model's name in full.
    public static func fullTitle(_ pill: PillState, serverName: String) -> String {
        switch pill {
        case .connected: "Online · \(serverName)"
        case .connecting: "Connecting to \(serverName)…"
        case .reconnecting: "Reconnecting…"
        case .unreachable: "Can't reach \(serverName)"
        case .needsAttention(let reason): attentionFull(reason, serverName: serverName)
        case .noServer: "Set up a server"
        case .localReady(let model): "Local · \(model.displayName)"
        case .localLoading(let model): "Loading \(model.displayName)…"
        case .localNoModel: "Local · No model"
        case .localFailed(let model, _): "\(model.displayName) didn't load"
        case .localOff: "Local · Turned off"
        }
    }

    /// The SF Symbol name for the pill.
    public static func symbol(_ pill: PillState) -> String {
        switch pill {
        case .connected: "point.3.connected.trianglepath.dotted"
        case .connecting, .reconnecting: "arrow.triangle.2.circlepath"
        case .unreachable: "wifi.exclamationmark"
        case .needsAttention(let reason): attentionSymbol(reason)
        case .noServer: "server.rack"
        case .localReady, .localLoading: "iphone"
        case .localNoModel, .localOff: "iphone.slash"
        case .localFailed: "exclamationmark.triangle"
        }
    }

    /// The colour family of the pill.
    public static func ink(_ pill: PillState) -> PillInk {
        switch pill {
        case .connected: .online
        case .connecting, .reconnecting, .localLoading: .warning
        case .needsAttention(.hostKey), .unreachable, .localNoModel, .localFailed: .problem
        case .needsAttention: .warning
        case .noServer, .localOff: .neutral
        case .localReady: .local
        }
    }

    /// The VoiceOver label. Every label names the chat's kind, as the spec requires.
    public static func voiceOverLabel(_ pill: PillState, serverName: String) -> String {
        switch pill {
        case .connected: "Online chat. Connected to \(serverName)."
        case .connecting: "Online chat. Connecting to \(serverName)."
        case .reconnecting: "Online chat. Connection lost, reconnecting."
        case .unreachable: "Online chat. Can't reach \(serverName). Check that Tailscale is on."
        case .needsAttention(let reason): "Online chat. \(attentionFull(reason, serverName: serverName))."
        case .noServer: "Online chat. No server set up yet."
        case .localReady(let model): "Local chat. Replies come from \(model.displayName) on this iPhone."
        case .localLoading(let model): "Local chat. Loading \(model.displayName) into memory."
        case .localNoModel: "Local chat. No on-device model is ready."
        case .localFailed(let model, _): "Local chat. \(model.displayName) failed to load."
        case .localOff: "Local chat. On-device features are turned off."
        }
    }

    /// True when VoiceOver announces the state as it is entered (O4, L3, L4 and a changed host key).
    public static func announcesOnEntry(_ pill: PillState) -> Bool {
        switch pill {
        case .unreachable, .localNoModel, .localFailed, .needsAttention(.hostKey): true
        default: false
        }
    }

    /// True when the state gives a warning haptic on entry (O4, L4 and a changed host key).
    public static func warnsOnEntry(_ pill: PillState) -> Bool {
        switch pill {
        case .unreachable, .localFailed, .needsAttention(.hostKey): true
        default: false
        }
    }

    /// Each reason has its own symbol, so a changed host key does not look like a routine sign-in.
    private static func attentionSymbol(_ reason: AttentionReason) -> String {
        switch reason {
        case .signIn: "person.crop.circle.badge.exclamationmark"
        case .serverUpdate: "arrow.up.circle"
        case .hostKey: "lock.trianglebadge.exclamationmark"
        case .settings: "gearshape"
        }
    }

    private static func attentionShort(_ reason: AttentionReason) -> String {
        switch reason {
        case .signIn: "Sign in"
        case .serverUpdate: "Update Hermes"
        case .hostKey: "Check key"
        case .settings: "Fix settings"
        }
    }

    private static func attentionFull(_ reason: AttentionReason, serverName: String) -> String {
        switch reason {
        case .signIn: "Sign in to \(serverName)"
        case .serverUpdate: "Update Hermes on \(serverName)"
        case .hostKey: "Check \(serverName)'s host key"
        case .settings: "Check the settings for \(serverName)"
        }
    }
}

extension StripConnection {
    /// The strip's connection dot for a pill. The chat's status is the one source: the strip reads it, not the phase.
    public init(pill: PillState) {
        switch pill {
        case .connected: self = .online
        case .connecting, .reconnecting: self = .reconnecting
        case .unreachable, .noServer, .localOff, .localNoModel, .localReady, .localLoading, .localFailed:
            self = .offline
        case .needsAttention: self = .needsAttention
        }
    }
}
