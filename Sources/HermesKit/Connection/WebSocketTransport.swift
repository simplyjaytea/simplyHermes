import Foundation

/// Why a WebSocket could not open or stopped.
public enum WebSocketError: Error, Sendable, Equatable {
    /// The HTTP upgrade was refused with this status. The gateway answers `403` for a bad, reused or missing ticket or token.
    case upgradeRejected(status: Int)
    /// The peer closed the socket with this close code, when it sent one.
    case closed(code: Int?, reason: String?)
    /// The socket could not be opened or broke. Carries a description of the underlying error.
    case failed(String)
    /// The platform cannot open WebSockets (for example `URLSessionWebSocketTask` on Linux).
    case notSupported
}

/// One open WebSocket carrying JSON-RPC text frames.
public protocol WebSocketConnection: Sendable {
    /// Inbound text frames, in order. The stream finishes when the peer closes the socket and throws when it breaks.
    var messages: AsyncThrowingStream<String, any Error> { get }
    /// Sends one text frame.
    func send(_ text: String) async throws
    /// Closes the socket. Safe to call more than once.
    func close() async
}

/// Opens WebSockets. The app uses ``URLSessionWebSocketTransport``; tests use scripted or SwiftNIO transports.
public protocol WebSocketTransport: Sendable {
    /// Opens a socket and returns once the HTTP upgrade has succeeded.
    ///
    /// Throws ``WebSocketError/upgradeRejected(status:)`` when the server refuses the upgrade.
    func connect(url: URL, headers: [String: String]) async throws -> any WebSocketConnection
}
