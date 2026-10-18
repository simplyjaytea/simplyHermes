import Foundation

/// `GET /api/status` as the server-control screens read it: the compatibility fields (``ServerStatus``) and the
/// gateway's own state. Each field is a key of Fixtures/rest/GET_api_status.json, read by its type. Values vary
/// between recorder runs, so the docs name types. The OpenAPI leaves the body untyped.
public struct ServerControlStatus: Sendable, Equatable, Decodable {
    /// The release, config and gateway fields that ``ServerCompatibility`` and the status line read.
    public var server: ServerStatus
    /// The gateway's state, mode and drain fields.
    public var gateway: ServerGatewayState

    /// Decodes both parts from the same answer. Unknown fields are ignored.
    public init(from decoder: any Decoder) throws {
        server = try ServerStatus(from: decoder)
        gateway = try ServerGatewayState(from: decoder)
    }

    /// Creates a value from its fields, for previews and tests.
    public init(
        releaseDate: String? = nil, latestConfigVersion: Int? = nil, overall: String? = nil,
        gatewayRunning: Bool? = nil, gatewayState: String? = nil, gatewayMode: String? = nil,
        gatewayBusy: Bool? = nil, gatewayDrainable: Bool? = nil, gatewayExitReason: String? = nil,
        canUpdateHermes: Bool? = nil
    ) {
        server = ServerStatus(
            releaseDate: releaseDate, latestConfigVersion: latestConfigVersion, gatewayRunning: gatewayRunning,
            overall: overall)
        gateway = ServerGatewayState(
            gatewayState: gatewayState, gatewayMode: gatewayMode, gatewayBusy: gatewayBusy,
            gatewayDrainable: gatewayDrainable, gatewayExitReason: gatewayExitReason,
            canUpdateHermes: canUpdateHermes)
    }
}

/// The gateway fields of `GET /api/status`. Each one is optional and read leniently: a field of an unexpected type
/// is nil, so it never fails the whole status.
public struct ServerGatewayState: Sendable, Equatable, Decodable {
    /// `gateway_state`. Null in GET_api_status.json, so its text type is not confirmed. Nil when null.
    public var gatewayState: String?
    /// `gateway_mode`, a string in GET_api_status.json.
    public var gatewayMode: String?
    /// `gateway_busy`, a boolean in GET_api_status.json.
    public var gatewayBusy: Bool?
    /// `gateway_drainable`, a boolean in GET_api_status.json.
    public var gatewayDrainable: Bool?
    /// `gateway_exit_reason`. Null in GET_api_status.json, so its text type is not confirmed.
    public var gatewayExitReason: String?
    /// `can_update_hermes`, a boolean in GET_api_status.json.
    public var canUpdateHermes: Bool?

    private enum CodingKeys: String, CodingKey {
        case gatewayState, gatewayMode, gatewayBusy, gatewayDrainable, gatewayExitReason, canUpdateHermes
    }

    /// Reads each field on its own, so one unexpected type does not stop the others.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        gatewayState = try? values.decodeIfPresent(String.self, forKey: .gatewayState)
        gatewayMode = try? values.decodeIfPresent(String.self, forKey: .gatewayMode)
        gatewayBusy = try? values.decodeIfPresent(Bool.self, forKey: .gatewayBusy)
        gatewayDrainable = try? values.decodeIfPresent(Bool.self, forKey: .gatewayDrainable)
        gatewayExitReason = try? values.decodeIfPresent(String.self, forKey: .gatewayExitReason)
        canUpdateHermes = try? values.decodeIfPresent(Bool.self, forKey: .canUpdateHermes)
    }

    /// Creates a value from its fields, for previews and tests.
    public init(
        gatewayState: String? = nil, gatewayMode: String? = nil, gatewayBusy: Bool? = nil,
        gatewayDrainable: Bool? = nil, gatewayExitReason: String? = nil, canUpdateHermes: Bool? = nil
    ) {
        self.gatewayState = gatewayState
        self.gatewayMode = gatewayMode
        self.gatewayBusy = gatewayBusy
        self.gatewayDrainable = gatewayDrainable
        self.gatewayExitReason = gatewayExitReason
        self.canUpdateHermes = canUpdateHermes
    }
}
