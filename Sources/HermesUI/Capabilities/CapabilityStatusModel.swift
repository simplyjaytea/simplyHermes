#if canImport(UIKit)
    import Foundation
    import HermesKit
    import Observation

    /// Computer Use status of the active server, read only (WP-53b). The permission grant is not part of this model.
    @MainActor
    @Observable
    public final class CapabilityStatusModel {
        public private(set) var status: CapabilityComputerUseStatus?
        public private(set) var isLoading = false
        /// Set when the last read failed. The status on screen stays.
        public private(set) var errorText: String?
        @ObservationIgnored private let connections: ConnectionsModel

        /// Creates a model. `status` seeds the screen, for previews.
        public init(connections: ConnectionsModel, status: CapabilityComputerUseStatus? = nil) {
            self.connections = connections
            self.status = status
        }

        /// Reads the status. Does nothing until a server is set up and connected.
        public func refresh() async {
            guard connections.active != nil, connections.manager != nil else { return }
            isLoading = true
            defer { isLoading = false }
            do {
                let rest = try await ToolsetAdminClient.rest(connections)
                status = try await rest.capabilityComputerUseStatus()
                errorText = nil
            } catch is CancellationError {
                return
            } catch {
                errorText = ToolsetAdminClient.message(for: error)
            }
        }
    }

    extension CapabilityStatusModel {
        /// A model with a sample status, for previews. It never reaches a server.
        static func preview() -> CapabilityStatusModel {
            CapabilityStatusModel(connections: .preview(), status: ToolsetAdminSamples.computerUse)
        }
    }
#endif
