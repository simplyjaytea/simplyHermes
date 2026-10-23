import Foundation

/// `GET /api/tools/computer-use/status`: Computer Use readiness, for display only. Typed from
/// `Fixtures/rest/GET_api_tools_computer-use_status.json`. In that answer `accessibility`, `error`, `ready`,
/// `screen_recording`, `screen_recording_capturable`, `source` and `version` are null, and `checks` is empty, so
/// they have no type here.
public struct CapabilityComputerUseStatus: Sendable, Equatable, Codable {
    /// Operating system the server runs on, such as `linux`.
    public var platform: String?
    /// True when Computer Use runs on that operating system.
    public var platformSupported: Bool?
    /// True when the driver is installed.
    public var installed: Bool?
    /// True when a permission grant can be requested.
    public var canGrant: Bool?
}
