/// The HTTP check before the WebSocket opens (WP-15): reach the server, check compatibility, sign in.
extension CheckedServer {
    /// Checks a gateway through its auth session: loads the stored sign-in, reads health and status, and signs in
    /// (refreshing tokens or signing in again with a remembered password when needed).
    public static func gateway(_ session: GatewayAuthSession, endpoint: HermesEndpoint) async throws -> CheckedServer {
        try await session.prepare()
        let client = session.client
        let (health, status) = try await reach(client)
        var summary = makeSummary(health, status)
        if summary.compatibility.allowsConnecting && (health.authRequired ?? status?.authRequired ?? false) {
            do {
                let user = try await client.currentUser()
                summary.signedInAs = user.displayName.flatMap { $0.isEmpty ? nil : $0 } ?? user.userId
            } catch is GatewaySignInRequired {
                throw ConnectionTestFailure.signInRequired(providers: status?.authProviders ?? [])
            } catch {
                throw GatewayConnectionTester.signInFailure(error)
            }
        }
        return CheckedServer(
            summary: summary, endpoint: endpoint, rest: client, credentials: session.credentialProvider())
    }

    /// Checks the dashboard behind an SSH tunnel. Its session token is the only credential.
    public static func tunnel(_ tunnel: OpenedTunnel, transport: any HTTPTransport) async throws -> CheckedServer {
        let token = tunnel.sessionToken
        let client = RESTClient(endpoint: tunnel.endpoint, transport: transport, auth: .sessionToken(token))
        let (health, status) = try await reach(client)
        return CheckedServer(
            summary: makeSummary(health, status), endpoint: tunnel.endpoint, rest: client,
            credentials: { _ in .token(token) })
    }

    private static func reach(_ client: RESTClient) async throws -> (ServerHealth, ServerStatus?) {
        let health: ServerHealth
        do {
            health = try await client.health()
        } catch {
            throw GatewayConnectionTester.reachFailure(error)
        }
        guard health.ok else { throw ConnectionTestFailure.notHermes }
        return (health, try? await client.status())
    }

    private static func makeSummary(_ health: ServerHealth, _ status: ServerStatus?) -> ServerSummary {
        ServerSummary(
            serverVersion: health.displayVersion ?? health.version, releaseDate: status?.releaseDate,
            compatibility: status.map { ServerCompatibility.check($0) } ?? .compatible)
    }
}
