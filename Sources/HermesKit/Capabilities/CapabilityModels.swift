import Foundation

/// `GET /api/tools/computer-use/status`: Computer Use readiness, for display only.
///
/// The server sends only what it could probe, so every field is optional. ``ready`` is the one signal to act on:
/// nil means the server could not tell.
public struct CapabilityComputerUseStatus: Sendable, Equatable, Codable {
    /// Operating system the server runs on: `darwin`, `win32` or `linux`.
    public var platform: String?
    /// True when Computer Use runs on that operating system.
    public var platformSupported: Bool?
    /// True when the driver is installed.
    public var installed: Bool?
    /// Driver version, when it answered.
    public var version: String?
    /// True when Computer Use can act now. Nil when unknown.
    public var ready: Bool?
    /// True on macOS, where the permissions are granted on the Mac that runs Hermes.
    public var canGrant: Bool?
    /// Probes the driver ran, with their outcome.
    public var checks: [CapabilityCheck]?
    /// Why the status could not be read fully.
    public var error: String?
    /// macOS Accessibility permission.
    public var accessibility: Bool?
    /// macOS Screen Recording permission.
    public var screenRecording: Bool?
    /// True when a screen capture actually works.
    public var screenRecordingCapturable: Bool?
}

/// One probe the Computer Use driver ran.
public struct CapabilityCheck: Sendable, Equatable, Codable {
    /// What was checked.
    public var label: String?
    /// Outcome, such as `ok` or `fail`.
    public var status: String?
    /// Detail for the user.
    public var message: String?
}
