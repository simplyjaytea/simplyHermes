import Foundation

/// Opens terminals on one server. Each connect asks for a fresh credential, as ``GatewayClient`` does, because a
/// ticket works once.
public struct TerminalConnector: Sendable {
    /// Where the server answers.
    public let endpoint: HermesEndpoint
    /// Credentials for each connect.
    public let credentials: GatewayCredentialProvider
    /// Opens the socket.
    public let transport: any TerminalSocketTransport

    /// Creates a connector.
    public init(
        endpoint: HermesEndpoint, credentials: @escaping GatewayCredentialProvider,
        transport: any TerminalSocketTransport
    ) {
        self.endpoint = endpoint
        self.credentials = credentials
        self.transport = transport
    }

    /// Opens the PTY named by `attach`. The window size goes out before the first output is read, so the TUI draws at
    /// the right size.
    ///
    /// A refused upgrade gets a fresh credential and one more try. A second refusal asks for a new sign-in. The
    /// provider's ``GatewaySignInRequired`` passes through.
    public func open(attach: String, profile: String?, columns: Int, rows: Int) async throws -> TerminalConnection {
        var request = GatewayCredentialRequest.initial
        var retries = 0
        while true {
            let credential = try await credentials(request)
            let url = TerminalProtocol.url(endpoint: endpoint, credential: credential, attach: attach, profile: profile)
            do {
                let socket = try await transport.connect(url: url, headers: endpoint.requestHeaders())
                let connection = TerminalConnection(socket: socket)
                do {
                    try await connection.resize(columns: columns, rows: rows)
                } catch {
                    await connection.close()
                    throw error
                }
                return connection
            } catch WebSocketError.upgradeRejected(let status) where status == 403 && retries < 2 {
                retries += 1
                request = retries == 1 ? .afterRejection : .reauthenticate
            }
        }
    }
}

/// One open terminal. Output is raw PTY bytes; keystrokes and the window size go out. Closing it leaves the PTY
/// running on the server.
public struct TerminalConnection: Sendable {
    private let socket: any TerminalSocket

    init(socket: any TerminalSocket) {
        self.socket = socket
    }

    /// PTY output, in order. Finishes when the peer closes normally and throws on any other close.
    public var output: AsyncThrowingStream<Data, any Error> { socket.frames }

    /// Sends keystrokes or pasted text.
    public func send(_ bytes: Data) async throws {
        try await socket.send(bytes)
    }

    /// Tells the PTY the window size.
    public func resize(columns: Int, rows: Int) async throws {
        try await socket.send(TerminalProtocol.resizeFrame(columns: columns, rows: rows))
    }

    /// Closes this socket. The PTY keeps running until the server's timeout.
    public func close() async {
        await socket.close()
    }
}
