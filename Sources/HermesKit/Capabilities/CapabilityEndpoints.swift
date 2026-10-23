import Foundation

/// Computer Use status. Read-only: the permission grant request is not part of this client.
extension RESTClient {
    /// `GET /api/tools/computer-use/status`. Typed from `Fixtures/rest/GET_api_tools_computer-use_status.json`.
    public func capabilityComputerUseStatus() async throws -> CapabilityComputerUseStatus {
        try await get("/api/tools/computer-use/status")
    }
}
