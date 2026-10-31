import Foundation
import HermesKit
import Testing

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

/// A tiny HTTP server on the loopback address that records raw requests and answers one fixed response.
///
/// The tests use it to exercise the real `URLSession` transport rather than a mock, so cookie sending and storing are
/// observed on the wire.
final class LocalHTTPFixture: @unchecked Sendable {
    enum Failure: Error {
        case socket
        case bind
        case listen
    }

    let port: Int

    private let listenFD: Int32
    private let response: Data
    private let lock = NSLock()
    private var seen: [String] = []
    private var stopped = false

    init(response: String) throws {
        self.response = Data(response.utf8)
        #if canImport(Darwin)
            let socketDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        #else
            let socketDescriptor = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        #endif
        guard socketDescriptor >= 0 else { throw Failure.socket }
        var reuse: Int32 = 1
        setsockopt(socketDescriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketDescriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            close(socketDescriptor)
            throw Failure.bind
        }
        guard listen(socketDescriptor, 4) == 0 else {
            close(socketDescriptor)
            throw Failure.listen
        }
        var actual = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &actual) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(socketDescriptor, $0, &length) }
        }
        port = Int(UInt16(bigEndian: actual.sin_port))
        listenFD = socketDescriptor
        Thread.detachNewThread { [self] in serve() }
    }

    /// The raw request heads the server has received, oldest first.
    var requests: [String] { lock.withLock { seen } }

    func stop() { lock.withLock { stopped = true } }

    private func serve() {
        while !lock.withLock({ stopped }) {
            var descriptor = pollfd(fd: listenFD, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, 50)
            guard ready > 0 else { continue }
            let client = accept(listenFD, nil, nil)
            guard client >= 0 else { continue }
            answer(client)
            close(client)
        }
        close(listenFD)
    }

    private func answer(_ client: Int32) {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        let terminator = Data("\r\n\r\n".utf8)
        while data.range(of: terminator) == nil {
            let count = recv(client, &buffer, buffer.count, 0)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        lock.withLock { seen.append(String(bytes: data, encoding: .utf8) ?? "") }
        response.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var sent = 0
            while sent < raw.count {
                let count = send(client, base.advanced(by: sent), raw.count - sent, 0)
                guard count > 0 else { break }
                sent += count
            }
        }
    }
}

/// The answer the fixture sends, with an optional cookie or redirect.
func fixtureResponse(status: String = "200 OK", setCookie: String? = nil, location: String? = nil) -> String {
    var head = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: 2\r\nConnection: close\r\n"
    if let setCookie { head += "Set-Cookie: \(setCookie)\r\n" }
    if let location { head += "Location: \(location)\r\n" }
    return head + "\r\n{}"
}

@Suite struct URLSessionAnonymousTransportTests {
    /// A pre-existing cookie in the process-wide store must not reach an anonymous request. On Linux the authenticated
    /// transport falls back to that store, so this also proves the anonymous transport stores nothing there.
    @Test func anonymousTransportSendsAndStoresNoCookies() async throws {
        let server = try LocalHTTPFixture(response: fixtureResponse(setCookie: "leak=1; Path=/"))
        defer { server.stop() }
        let url = try #require(URL(string: "http://127.0.0.1:\(server.port)/health"))

        let preseed = try #require(
            HTTPCookie(properties: [.name: "preseed", .value: "1", .domain: "127.0.0.1", .path: "/"]))
        let injected = try #require(
            HTTPCookie(properties: [.name: "injected", .value: "1", .domain: "127.0.0.1", .path: "/"]))
        #if !canImport(Darwin)
            HTTPCookieStorage.shared.setCookie(preseed)
            defer { HTTPCookieStorage.shared.deleteCookie(preseed) }
            #expect(HTTPCookieStorage.shared.cookies?.contains(where: { $0.name == "preseed" }) == true)
        #endif

        let anonymous = URLSessionHTTPTransport.anonymous(timeout: 5)
        // An anonymous transport stands in where a cookie-importing transport is expected; the import must be ignored.
        anonymous.importCookies([injected])
        _ = try await anonymous.send(HTTPRequest(method: "GET", url: url))
        _ = try await anonymous.send(HTTPRequest(method: "GET", url: url))

        #expect(server.requests.count == 2)
        for request in server.requests {
            #expect(!request.lowercased().contains("\r\ncookie:"), "anonymous request carried cookies: \(request)")
        }

        // A later normal session does not inherit the anonymous answer's Set-Cookie.
        let authenticated = URLSessionHTTPTransport(timeout: 5)
        _ = try await authenticated.send(HTTPRequest(method: "GET", url: url))
        let last = try #require(server.requests.last)
        #expect(!last.contains("leak=1"))

        #if !canImport(Darwin)
            // A session using the process-wide store still has the pre-seeded cookie, but not the anonymous one.
            let sharedSession = URLSession(configuration: .default)
            _ = try await sharedSession.data(for: URLRequest(url: url))
            let sharedRequest = try #require(server.requests.last)
            #expect(sharedRequest.contains("Cookie: preseed=1"))
            #expect(!sharedRequest.contains("leak=1"))
        #endif
    }

    @Test func anonymousTransportDoesNotFollowRedirects() async throws {
        let target = try LocalHTTPFixture(response: fixtureResponse())
        defer { target.stop() }
        let redirect = try #require(URL(string: "http://127.0.0.1:\(target.port)/stolen"))
        let source = try LocalHTTPFixture(
            response: fixtureResponse(status: "302 Found", location: redirect.absoluteString))
        defer { source.stop() }
        let url = try #require(URL(string: "http://127.0.0.1:\(source.port)/health"))

        let anonymous = URLSessionHTTPTransport.anonymous(timeout: 5)
        let response = try await anonymous.send(
            HTTPRequest(method: "GET", url: url, headers: ["Authorization": "Bearer must-not-follow"]))
        #expect(response.status == 302)
        #expect(source.requests.count == 1)
        #expect(target.requests.isEmpty)
    }
}
