import Foundation
import Testing

@testable import HermesKit

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// The positive controls and the guards for the AT-2b trap. A zero that a local chat reports means something only if
/// every connection is counted, so these tests fail when one is not.
struct NetworkTrapTests {
    // A port nothing listens on, so the attempt fails at once and makes no real request.
    private let closed = URL(string: "http://127.0.0.1:9/")!

    // MARK: Positive controls

    @Test func anHTTPRequestIsCounted() async throws {
        let before = NetworkTrap.count(at: "http")
        _ = try? await URLSessionHTTPTransport(timeout: 2).send(HTTPRequest(method: "GET", url: closed, timeout: 2))
        #expect(NetworkTrap.count(at: "http") >= before + 1)
    }

    @Test func aModelDownloadIsCounted() async throws {
        let before = NetworkTrap.count(at: "download")
        let downloader = URLSessionModelFileDownloader()
        _ = try? await downloader.download(
            from: closed.appendingPathComponent("probe.bin"), resumeData: nil, progress: { _ in })
        #expect(NetworkTrap.count(at: "download") >= before + 1)
    }

    // Moss's case A, at runtime: a session made by the factory counts a request that nothing recorded by hand. The
    // wiring is checked first, because the shared counter also moves for other tests running at the same time.
    @Test func aSessionFromTheFactoryCountsItsRequests() async throws {
        let session = NetworkSessions.make(configuration: .ephemeral)
        let wired = session.configuration.protocolClasses?.contains { $0 == CountingProtocol.self } ?? false
        #expect(wired, "The factory should put the counting protocol first")
        let before = NetworkTrap.count(at: "intercepted")
        _ = try? await session.data(for: URLRequest(url: closed, timeoutInterval: 2))
        #expect(NetworkTrap.count(at: "intercepted") >= before + 1)
    }

    // MARK: Rule 1: sessions are made only by the factory

    @Test func everyURLSessionIsMadeByTheFactory() throws {
        var found: [String] = []
        for file in try ConnectionGuard.sourceFiles() {
            found += ConnectionGuard.sessionViolations(path: file.path, text: file.text)
        }
        #expect(found.isEmpty, "\(found)")
    }

    @Test func aSessionCreatedOutsideTheFactoryFails() {
        let text = "func make() -> URLSession {\n    URLSession(configuration: .default)\n}"
        #expect(ConnectionGuard.sessionViolations(path: "HermesKit/Scratch.swift", text: text).count == 1)
    }

    @Test func theSharedSessionOutsideTheFactoryFails() {
        let text = "let body = try await URLSession.shared.data(for: request)"
        #expect(ConnectionGuard.sessionViolations(path: "HermesSSH/Scratch.swift", text: text).count == 1)
    }

    @Test func aSessionCreatedWithInitOutsideTheFactoryFails() {
        let text = "let s = URLSession.init(configuration: .default)"
        #expect(ConnectionGuard.sessionViolations(path: "HermesKit/Scratch.swift", text: text).count == 1)
    }

    @Test func theFactoryMayCreateASession() {
        let text = "return URLSession(configuration: configuration, delegate: delegate, delegateQueue: delegateQueue)"
        #expect(ConnectionGuard.sessionViolations(path: ConnectionGuard.factoryPath, text: text).isEmpty)
    }

    // A function that only uses a session it was handed creates none, so it is not a violation. The sessions it can
    // use all come from the factory.
    @Test func aFunctionThatUsesASessionMadeElsewhereIsNotAViolation() {
        let text =
            "func fetch(_ session: URLSession, _ request: URLRequest) async throws {\n"
            + "    _ = try await session.data(for: request)\n}"
        #expect(ConnectionGuard.sessionViolations(path: "HermesKit/Scratch.swift", text: text).isEmpty)
    }

    // MARK: Rule 2: each other opener is recorded by its own record, in the same function

    @Test func everyOtherConnectionOpenerRecordsItsOwnConnection() throws {
        var found: [String] = []
        for file in try ConnectionGuard.sourceFiles() {
            found += ConnectionGuard.openerViolations(path: file.path, text: file.text)
        }
        #expect(found.isEmpty, "\(found)")
    }

    @Test func aSecondUnrecordedOpenerInARecordingFunctionFails() {
        // Moss's case B: one record covers the opener after it. The second opener has none.
        let text = """
            func a() {
                NetworkTrap.record("ssh")
                let first = ClientBootstrap(group: group)
                let second = ClientBootstrap(group: group)
            }
            """
        #expect(ConnectionGuard.openerViolations(path: "HermesSSH/Scratch.swift", text: text).count == 1)
    }

    @Test func eachRecordedOpenerPasses() {
        let text = """
            func a() {
                NetworkTrap.record("ssh")
                let first = ClientBootstrap(group: group)
                NetworkTrap.record("ssh")
                let second = ClientBootstrap(group: group)
            }
            """
        #expect(ConnectionGuard.openerViolations(path: "HermesSSH/Scratch.swift", text: text).isEmpty)
    }

    @Test func anUnrecordedNWConnectionFails() {
        let text = "let connection = NWConnection(host: host, port: port, using: .tcp)"
        #expect(ConnectionGuard.openerViolations(path: "HermesKit/Scratch.swift", text: text).count == 1)
    }

    @Test func aRecordInAnotherFunctionDoesNotCover() {
        let text = """
            func a() {
                NetworkTrap.record("ssh")
            }
            func b() {
                let connection = NWConnection(host: host, port: port, using: .tcp)
            }
            """
        #expect(ConnectionGuard.openerViolations(path: "HermesKit/Scratch.swift", text: text).count == 1)
    }

    @Test func aRecordTooFarAboveDoesNotCover() {
        let text = """
            func a() {
                NetworkTrap.record("ssh")
                let a = 1
                let b = 2
                let c = 3
                let d = 4
                let e = 5
                let connection = NWConnection(host: host, port: port, using: .tcp)
            }
            """
        #expect(ConnectionGuard.openerViolations(path: "HermesKit/Scratch.swift", text: text).count == 1)
    }

    // The listening bootstrap is exempt for its own file only, and only for its own opener.
    @Test func theLoopbackListenerIsExemptButNoOtherOpenerInItsFileIs() {
        #expect(
            ConnectionGuard.openerViolations(
                path: "HermesSSH/LoopbackForwarder.swift", text: "let channel = try await ServerBootstrap(group: group)"
            ).isEmpty)
        #expect(
            ConnectionGuard.openerViolations(
                path: "HermesSSH/LoopbackForwarder.swift", text: "let c = ClientBootstrap(group: group)"
            ).count == 1)
    }

    // MARK: Every site the readout names is real

    // Every site a file records is one the readout lists, and every listed site is recorded somewhere, so the per-site
    // readout names only real transports.
    @Test func everyRecordedSiteIsAKnownSiteAndEverySiteIsRecorded() throws {
        var recorded: Set<String> = []
        for file in try ConnectionGuard.sourceFiles() {
            for match in file.text.matches(of: #/NetworkTrap\.record\("([a-z]+)"\)/#) {
                recorded.insert(String(match.1))
            }
        }
        #expect(recorded.isSubset(of: Set(NetworkTrap.sites)), "Unknown site recorded: \(recorded)")
        #expect(
            Set(NetworkTrap.sites).isSubset(of: recorded),
            "Listed sites never recorded: \(Set(NetworkTrap.sites).subtracting(recorded))")
    }
}
