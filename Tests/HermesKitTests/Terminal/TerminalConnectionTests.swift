import Foundation
import Testing

@testable import HermesKit

/// Records the credential requests a connector makes, and hands out tickets in order.
private final class CredentialLog: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [GatewayCredentialRequest] = []
    private var issued = 0

    var made: [GatewayCredentialRequest] { lock.withLock { requests } }

    func next(_ request: GatewayCredentialRequest) -> GatewayCredential {
        lock.withLock {
            requests.append(request)
            issued += 1
            return .ticket("ticket-\(issued)")
        }
    }
}

@Suite struct TerminalConnectionTests {
    private func makeConnector(
        transport: ScriptedTerminalTransport, log: CredentialLog
    ) throws -> TerminalConnector {
        let endpoint = try #require(HermesEndpoint(string: "http://127.0.0.1:9119"))
        return TerminalConnector(
            endpoint: endpoint,
            credentials: { request in log.next(request) },
            transport: transport)
    }

    @Test func sendsTheWindowSizeBeforeAnyOutput() async throws {
        let socket = FakeTerminalSocket()
        let transport = ScriptedTerminalTransport([.accept(socket)])
        let connector = try makeConnector(transport: transport, log: CredentialLog())

        _ = try await connector.open(attach: "tab1", profile: nil, columns: 80, rows: 24)

        #expect(socket.sent == [TerminalProtocol.resizeFrame(columns: 80, rows: 24)])
    }

    @Test func refusedUpgradeGetsAFreshTicketOnce() async throws {
        let socket = FakeTerminalSocket()
        let transport = ScriptedTerminalTransport([.reject(status: 403), .accept(socket)])
        let log = CredentialLog()
        let connector = try makeConnector(transport: transport, log: log)

        _ = try await connector.open(attach: "tab1", profile: nil, columns: 80, rows: 24)

        #expect(log.made == [.initial, .afterRejection])
        let urls = transport.connectedURLs
        #expect(urls.count == 2)
        #expect(urls.last?.absoluteString.contains("ticket=ticket-2") == true)
    }

    @Test func secondRefusalAsksForASignIn() async throws {
        let socket = FakeTerminalSocket()
        let transport = ScriptedTerminalTransport([.reject(status: 403), .reject(status: 403), .accept(socket)])
        let log = CredentialLog()
        let connector = try makeConnector(transport: transport, log: log)

        _ = try await connector.open(attach: "tab1", profile: nil, columns: 80, rows: 24)

        #expect(log.made == [.initial, .afterRejection, .reauthenticate])
    }

    @Test func givesUpAfterThreeRefusals() async throws {
        let transport = ScriptedTerminalTransport([.reject(status: 403), .reject(status: 403), .reject(status: 403)])
        let connector = try makeConnector(transport: transport, log: CredentialLog())

        await #expect(throws: WebSocketError.upgradeRejected(status: 403)) {
            _ = try await connector.open(attach: "tab1", profile: nil, columns: 80, rows: 24)
        }
        #expect(transport.connectedURLs.count == 3)
    }

    @Test func otherRefusalsAreNotRetried() async throws {
        let transport = ScriptedTerminalTransport([.reject(status: 500)])
        let connector = try makeConnector(transport: transport, log: CredentialLog())

        await #expect(throws: WebSocketError.upgradeRejected(status: 500)) {
            _ = try await connector.open(attach: "tab1", profile: nil, columns: 80, rows: 24)
        }
        #expect(transport.connectedURLs.count == 1)
    }

    @Test func signInRequiredFromTheProviderPassesThrough() async throws {
        let endpoint = try #require(HermesEndpoint(string: "http://127.0.0.1:9119"))
        let connector = TerminalConnector(
            endpoint: endpoint,
            credentials: { _ in throw GatewaySignInRequired() },
            transport: ScriptedTerminalTransport([]))

        await #expect(throws: GatewaySignInRequired.self) {
            _ = try await connector.open(attach: "tab1", profile: nil, columns: 80, rows: 24)
        }
    }

    @Test func outputSendsAndCloseReachTheSocket() async throws {
        let socket = FakeTerminalSocket()
        let connector = try makeConnector(
            transport: ScriptedTerminalTransport([.accept(socket)]), log: CredentialLog())
        let connection = try await connector.open(attach: "tab1", profile: nil, columns: 80, rows: 24)

        socket.push(Data("hello".utf8))
        var iterator = connection.output.makeAsyncIterator()
        let first = try await iterator.next()
        #expect(first == Data("hello".utf8))

        let keys = Data("ls\r".utf8)
        try await connection.send(keys)
        #expect(socket.sent.last == keys)

        try await connection.resize(columns: 100, rows: 30)
        #expect(socket.sent.last == TerminalProtocol.resizeFrame(columns: 100, rows: 30))

        await connection.close()
        #expect(socket.isClosed)
    }

    @Test func brokenSocketEndsOutputWithItsError() async throws {
        let socket = FakeTerminalSocket()
        let connector = try makeConnector(
            transport: ScriptedTerminalTransport([.accept(socket)]), log: CredentialLog())
        let connection = try await connector.open(attach: "tab1", profile: nil, columns: 80, rows: 24)

        socket.end(throwing: WebSocketError.closed(code: 1011, reason: nil))

        var iterator = connection.output.makeAsyncIterator()
        await #expect(throws: WebSocketError.closed(code: 1011, reason: nil)) {
            _ = try await iterator.next()
        }
    }
}
