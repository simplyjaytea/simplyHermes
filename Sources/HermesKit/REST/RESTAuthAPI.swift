import Foundation

/// Answer of `POST /api/auth/ws-ticket`.
public struct WebSocketTicket: Sendable, Equatable, Codable {
    /// The single-use ticket for `?ticket=`.
    public var ticket: String
    /// Seconds the ticket stays valid (30).
    public var ttlSeconds: Int

    /// Creates a ticket value.
    public init(ticket: String, ttlSeconds: Int) {
        self.ticket = ticket
        self.ttlSeconds = ttlSeconds
    }

    enum CodingKeys: String, CodingKey {
        case ticket
        case ttlSeconds = "ttl_seconds"
    }
}

private struct PasswordLoginBody: Encodable {
    var provider = "basic"
    var username: String
    var password: String
    var next = ""
}

private struct LoginAnswer: Decodable { var ok: Bool? }

extension RESTClient {
    /// Signs in with the dashboard's basic auth. The transport keeps the session cookies.
    /// Throws ``RESTError/unauthorized`` for wrong credentials and ``RESTError/rateLimited(retryAfter:)`` after the
    /// server's 10-per-minute limit.
    public func passwordLogin(username: String, password: String) async throws {
        let _: LoginAnswer = try await send(
            "POST", "/auth/password-login", body: PasswordLoginBody(username: username, password: password),
            scoped: false)
    }

    /// Mints a WebSocket ticket. Call before every connect and reconnect.
    public func webSocketTicket() async throws -> WebSocketTicket {
        try await send("POST", "/api/auth/ws-ticket", scoped: false)
    }

    /// Credentials for the gateway client in gateway mode.
    ///
    /// A fresh ticket for `.initial` and `.afterRejection`. For `.reauthenticate` it signs in again with `login`
    /// first. A rejected login throws ``GatewaySignInRequired`` so the client stops and asks the user.
    public func gatewayCredentialProvider(login: (@Sendable () async throws -> Void)?) -> GatewayCredentialProvider {
        { [self] request in
            if request == .reauthenticate {
                guard let login else { throw GatewaySignInRequired() }
                do { try await login() } catch RESTError.unauthorized { throw GatewaySignInRequired() }
            }
            do {
                return .ticket(try await webSocketTicket().ticket)
            } catch RESTError.unauthorized {
                throw GatewaySignInRequired()
            }
        }
    }
}
