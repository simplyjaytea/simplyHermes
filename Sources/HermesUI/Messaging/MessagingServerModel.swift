#if canImport(UIKit)
    import Foundation
    import HermesKit
    import Observation

    /// The messaging screens have no server to talk to.
    private enum MessagingScreenError: Error {
        case noServer
    }

    extension String {
        /// The text without spaces or line breaks at either end.
        var messagingTrimmed: String {
            trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// State shared by the messaging screens (WP-53c): the status rows of the last list and the result of the last
    /// request. The rows come from typed answers, so a screen shows only the fields those answers show.
    @MainActor
    @Observable
    public final class MessagingServerModel {
        /// The status rows the screen shows. Nil until a load works.
        public private(set) var lines: [MessagingStatusLine]?
        /// True while the list loads.
        public private(set) var isLoading = false
        /// Set when the last request failed. The next request that works clears it.
        public private(set) var errorText: String?
        /// Set when the last change worked, for example "Webhook created."
        public private(set) var noticeText: String?

        @ObservationIgnored private let connections: ConnectionsModel
        @ObservationIgnored private let read: (@Sendable (RESTClient) async throws -> [MessagingStatusLine])?

        /// Creates a model for the active server. `read` loads the screen's status rows. Nil for a screen
        /// without a list.
        public init(
            connections: ConnectionsModel,
            read: (@Sendable (RESTClient) async throws -> [MessagingStatusLine])? = nil
        ) {
            self.connections = connections
            self.read = read
        }

        /// Loads the rows again. Does nothing without a list, or without a server (previews, offline).
        public func refresh() async {
            guard let read, connections.manager != nil else { return }
            isLoading = true
            defer { isLoading = false }
            do {
                let rest = try await client()
                lines = try await read(rest)
                errorText = nil
            } catch is CancellationError {
                return
            } catch {
                errorText = Self.message(for: error)
            }
        }

        /// Runs a change on the active server. On success it shows `success` and loads the list again. Only the HTTP
        /// status decides the result: the answer body is not read. Returns true when the change worked.
        @discardableResult
        public func perform(
            _ success: String, _ change: @escaping @Sendable (RESTClient) async throws -> Void
        ) async -> Bool {
            do {
                let rest = try await client()
                try await change(rest)
            } catch is CancellationError {
                return false
            } catch {
                noticeText = nil
                errorText = Self.message(for: error)
                return false
            }
            errorText = nil
            noticeText = success
            await refresh()
            return true
        }

        /// The signed-in REST client of the active server. Connects on demand, as the session list does.
        private func client() async throws -> RESTClient {
            guard let connection = connections.active, let manager = connections.manager else {
                throw MessagingScreenError.noServer
            }
            _ = try await manager.client(for: connection)
            guard let rest = await manager.rest(for: connection.id) else {
                throw ConnectionUnavailable(phase: await manager.phase(of: connection.id))
            }
            return rest
        }

        private static func message(for error: any Error) -> String {
            switch error {
            case is MessagingScreenError:
                "Open a server in Settings > Servers first."
            case let unavailable as ConnectionUnavailable:
                connectionMessage(unavailable.phase)
            case let rest as RESTError:
                restMessage(rest)
            default:
                "Something went wrong. Try again."
            }
        }

        private static func connectionMessage(_ phase: ConnectionPhase) -> String {
            switch phase {
            case .failed(let failure): failure.message
            case .signInRequired: "Sign in to this server again."
            case .updateRequired: "Update simplyHermes or your Hermes server."
            default: "The server is not connected. Try again in a moment."
            }
        }

        private static func restMessage(_ error: RESTError) -> String {
            switch error {
            case .unauthorized: "Sign in to this server again."
            case .rateLimited: "The server is busy. Try again in a moment."
            case .http(_, let detail?): detail
            case .http(let status, nil): "The server answered with status \(status)."
            case .unexpectedContent: "The server sent a web page instead of an answer."
            case .transport: "Could not reach the server."
            case .decoding: "The server sent an answer in a form the app does not read."
            }
        }

        /// A model with fixed rows and no server, for previews. It makes no request.
        public static func preview(
            lines: [MessagingStatusLine]? = nil, errorText: String? = nil
        ) -> MessagingServerModel {
            let model = MessagingServerModel(connections: .preview())
            model.lines = lines
            model.errorText = errorText
            return model
        }
    }
#endif
