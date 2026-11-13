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

    @Test func aTypealiasOfURLSessionOutsideTheFactoryFails() {
        let text = "typealias Web = URLSession\nlet s = Web(configuration: .default)"
        #expect(ConnectionGuard.sessionViolations(path: "HermesKit/Scratch.swift", text: text).count == 1)
        let qualified = "typealias Web = Foundation.URLSession"
        #expect(ConnectionGuard.sessionViolations(path: "HermesKit/Scratch.swift", text: qualified).count == 1)
    }

    @Test func anExtensionOfURLSessionOutsideTheFactoryFails() {
        let text = "extension URLSession {\n    convenience init(plain: Bool) { self.init(configuration: .default) }\n}"
        #expect(ConnectionGuard.sessionViolations(path: "HermesKit/Scratch.swift", text: text).count == 1)
    }

    @Test func theFactoryMayAliasAndExtendASession() {
        let text = "typealias Web = URLSession\nextension URLSession {}"
        #expect(ConnectionGuard.sessionViolations(path: ConnectionGuard.factoryPath, text: text).isEmpty)
    }

    // Types that only start with URLSession are not the session itself.
    @Test func aTypeThatMerelyStartsWithURLSessionIsNotAViolation() {
        let text = "typealias Socket = URLSessionWebSocketTask\nextension URLSessionWebSocketConnection: Sendable {}"
        #expect(ConnectionGuard.sessionViolations(path: "HermesKit/Scratch.swift", text: text).isEmpty)
    }

    // Moss's bypass 1 (QA round 4, #138): the type as a value, then `.init`.
    @Test func theSessionTypeTakenAsAValueFails() {
        let text = "let sessionType = URLSession.self\nreturn sessionType.init(configuration: .default)"
        #expect(ConnectionGuard.sessionViolations(path: "HermesKit/Scratch.swift", text: text).count == 1)
        for form in ["Foundation.URLSession.self", "URLSession.Type", "URLSession . self"] {
            let other = "let t = \(form)"
            #expect(
                ConnectionGuard.sessionViolations(path: "HermesKit/Scratch.swift", text: other).count == 1, "\(form)")
        }
    }

    @Test func aSessionWrittenWithWhiteSpaceOrAModulePrefixFails() {
        for form in [
            "URLSession (configuration: .default)", "Foundation.URLSession(configuration: .default)",
            "URLSession . init(configuration: .default)", "URLSession\n.shared",
        ] {
            #expect(
                !ConnectionGuard.sessionViolations(path: "HermesKit/Scratch.swift", text: "let s = \(form)").isEmpty,
                "\(form)")
        }
    }

    // A connection written inside quoted text: code in an interpolation is code.
    @Test func aSessionCreatedInsideAStringInterpolationFails() {
        let text = #"let note = "opened \(URLSession(configuration: .default))""#
        #expect(ConnectionGuard.sessionViolations(path: "HermesKit/Scratch.swift", text: text).count == 1)
        let nested = #"let note = "a \("b \(URLSession.shared)")""#
        #expect(ConnectionGuard.sessionViolations(path: "HermesKit/Scratch.swift", text: nested).count == 1)
        let raw = ##"let note = #"x \#(URLSession.shared) y"#"##
        #expect(ConnectionGuard.sessionViolations(path: "HermesKit/Scratch.swift", text: raw).count == 1)
    }

    // Ways to reach a session without writing its name next to a call.
    @Test func aSubclassOrAConstrainedGenericOrTypeOfInitFails() {
        for text in [
            "final class Evil: URLSession {}",
            "class Evil<T>: NSObject, URLSession {}",
            "func make<T: URLSession>(_ type: T.Type) -> T { type.init(configuration: .default) }",
            "func make<T>(_ type: T.Type) -> T where T: URLSession { type.init(configuration: .default) }",
            "let copy = type(of: existing).init(configuration: .default)",
            "let make = URLSession.init",
        ] {
            #expect(!ConnectionGuard.sessionViolations(path: "HermesKit/Scratch.swift", text: text).isEmpty, "\(text)")
        }
    }

    @Test func aDelegateOrAParameterOfTheTypeIsNotASessionBypass() {
        for text in [
            "final class Watcher: NSObject, URLSessionDelegate {}",
            "func urlSession(_ session: URLSession, task: URLSessionTask) {}",
            "func fetch(_ session: URLSession, _ request: URLRequest) async throws {}",
        ] {
            #expect(ConnectionGuard.sessionViolations(path: "HermesKit/Scratch.swift", text: text).isEmpty, "\(text)")
        }
    }

    @Test func aNameInPlainTextOrACommentIsNotASession() {
        let text = """
            // URLSession(configuration: .default) in a comment
            /* URLSession.shared
               in a block comment */
            let message = "Use URLSession(configuration:) only in the factory"
            let multi = \"\"\"
                URLSession.shared is text here
                \"\"\"
            """
        #expect(ConnectionGuard.sessionViolations(path: "HermesKit/Scratch.swift", text: text).isEmpty)
    }

    @Test func aTypeThatOnlyStartsWithURLSessionIsNotASessionTypeValue() {
        let text = "let t = URLSessionWebSocketTask.self\nlet u = URLSessionConfiguration.default"
        #expect(ConnectionGuard.sessionViolations(path: "HermesKit/Scratch.swift", text: text).isEmpty)
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

    // Row 88: a record counts only when it is on the opener's path.
    @Test func aRecordInTheOtherArmOfAnIfDoesNotCover() {
        let text = """
            func a() {
                if flag {
                    NetworkTrap.record("ssh")
                } else {
                    let connection = ClientBootstrap(group: group)
                }
            }
            """
        #expect(ConnectionGuard.openerViolations(path: "HermesSSH/Scratch.swift", text: text).count == 1)
    }

    @Test func aRecordInABlockThatClosedBeforeTheOpenerDoesNotCover() {
        let text = """
            func a() {
                if flag { NetworkTrap.record("ssh") }
                let connection = ClientBootstrap(group: group)
            }
            """
        #expect(ConnectionGuard.openerViolations(path: "HermesSSH/Scratch.swift", text: text).count == 1)
    }

    @Test func aRecordInAnEnclosingBlockCoversAnOpenerInsideABranch() {
        let text = """
            func a() {
                NetworkTrap.record("ssh")
                if flag {
                    let connection = ClientBootstrap(group: group)
                }
            }
            """
        #expect(ConnectionGuard.openerViolations(path: "HermesSSH/Scratch.swift", text: text).isEmpty)
    }

    @Test func eachArmOfAnIfThatRecordsAndOpensPasses() {
        let text = """
            func a() {
                if flag {
                    NetworkTrap.record("ssh")
                    let one = ClientBootstrap(group: group)
                } else {
                    NetworkTrap.record("ssh")
                    let two = ClientBootstrap(group: group)
                }
            }
            """
        #expect(ConnectionGuard.openerViolations(path: "HermesSSH/Scratch.swift", text: text).isEmpty)
    }

    @Test func aBraceInAStringOrACommentDoesNotMoveTheBlock() {
        let text = """
            func a() {
                NetworkTrap.record("ssh")
                let marker = "}" // }
                let connection = ClientBootstrap(group: group)
            }
            """
        #expect(ConnectionGuard.openerViolations(path: "HermesSSH/Scratch.swift", text: text).isEmpty)
    }

    // Moss's bypass 2 (QA round 4, #138): the qualified type as a value, then `.init`.
    @Test func aQualifiedBootstrapTakenAsAValueFails() {
        let text = "let bootstrapType = NIOPosix.ClientBootstrap.self\n_ = bootstrapType.init(group: group)"
        #expect(!ConnectionGuard.openerViolations(path: "HermesSSH/Scratch.swift", text: text).isEmpty)
        for name in ["ClientBootstrap", "NIOTSConnectionBootstrap", "NWConnection", "ServerBootstrap", "SSHClient"] {
            for form in ["\(name).self", "NIOPosix.\(name).Type"] {
                let other = "func a() {\n    NetworkTrap.record(\"ssh\")\n    let t = \(form)\n}"
                #expect(
                    ConnectionGuard.openerViolations(path: "HermesSSH/Scratch.swift", text: other).count == 1,
                    "\(form)")
            }
        }
    }

    @Test func anAliasOfAConnectionTypeFails() {
        for name in ["ClientBootstrap", "NWConnection", "SSHClient"] {
            let text = "typealias Opener = NIOPosix.\(name)"
            #expect(ConnectionGuard.openerViolations(path: "HermesSSH/Scratch.swift", text: text).count == 1, "\(name)")
        }
    }

    @Test func aQualifiedOrInitCallStillNeedsItsRecord() {
        for call in [
            "NIOPosix.ClientBootstrap(group: group)", "ClientBootstrap.init(group: group)",
            "ClientBootstrap (group: group)",
        ] {
            let bare = "func a() {\n    let c = \(call)\n}"
            #expect(ConnectionGuard.openerViolations(path: "HermesSSH/Scratch.swift", text: bare).count == 1, "\(call)")
            let recorded = "func a() {\n    NetworkTrap.record(\"ssh\")\n    let c = \(call)\n}"
            #expect(
                ConnectionGuard.openerViolations(path: "HermesSSH/Scratch.swift", text: recorded).isEmpty, "\(call)")
        }
    }

    @Test func aReferenceToSSHConnectIsAnOpener() {
        let bare = "func a() {\n    let connect = SSHClient.connect\n}"
        #expect(ConnectionGuard.openerViolations(path: "HermesSSH/Scratch.swift", text: bare).count == 1)
        let recorded = "func a() {\n    NetworkTrap.record(\"ssh\")\n    let connect = SSHClient.connect\n}"
        #expect(ConnectionGuard.openerViolations(path: "HermesSSH/Scratch.swift", text: recorded).isEmpty)
    }

    // A connection written inside quoted text: code in an interpolation is code, text is not.
    @Test func anOpenerInsideAStringInterpolationNeedsItsRecord() {
        let text = #"func a() {\n    let note = "up \(ClientBootstrap(group: group))"\n}"#
        #expect(ConnectionGuard.openerViolations(path: "HermesSSH/Scratch.swift", text: text).count == 1)
    }

    @Test func anOpenerNameInPlainTextOrACommentOpensNothing() {
        let text = """
            func a() {
                // let c = ClientBootstrap(group: group)
                /* NWConnection(host: host, port: port, using: .tcp) */
                let message = "ClientBootstrap( is only text, and so is SSHClient.connect"
            }
            """
        #expect(ConnectionGuard.openerViolations(path: "HermesSSH/Scratch.swift", text: text).isEmpty)
    }

    @Test func aRecordInsideACommentOrAStringDoesNotCover() {
        let comment = "func a() {\n    /* NetworkTrap.record(\"ssh\") */\n    let c = ClientBootstrap(group: group)\n}"
        #expect(ConnectionGuard.openerViolations(path: "HermesSSH/Scratch.swift", text: comment).count == 1)
        let string =
            "func a() {\n    let s = \"NetworkTrap.record(\\\"ssh\\\")\"\n    let c = ClientBootstrap(group: group)\n}"
        #expect(ConnectionGuard.openerViolations(path: "HermesSSH/Scratch.swift", text: string).count == 1)
    }

    @Test func aBraceInABlockCommentOrAMultiLineStringDoesNotMoveTheBlock() {
        let text = """
            func a() {
                NetworkTrap.record("ssh")
                /* } */
                let note = \"\"\"
                    }
                    \"\"\"
                let c = ClientBootstrap(group: group)
            }
            """
        #expect(ConnectionGuard.openerViolations(path: "HermesSSH/Scratch.swift", text: text).isEmpty)
    }

    @Test func anOpenerSplitAcrossLinesStillNeedsItsRecord() {
        let bare = "func a() {\n    let c = ClientBootstrap\n        (group: group)\n}"
        #expect(ConnectionGuard.openerViolations(path: "HermesSSH/Scratch.swift", text: bare).count == 1)
        let recorded =
            "func a() {\n    NetworkTrap.record(\"ssh\")\n    let c = ClientBootstrap\n        (group: group)\n}"
        #expect(ConnectionGuard.openerViolations(path: "HermesSSH/Scratch.swift", text: recorded).isEmpty)
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

    // The UI test probes the sites by name. A transport added to NetworkTrap.sites but not to that list would never be
    // checked on a device, so the two lists must be the same (row 87).
    @Test func theUITestProbesExactlyTheSitesTheTrapKnows() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let file = root.appendingPathComponent("App/HermesAppUITests/LocalChatUITests.swift")
        let text = try String(contentsOf: file, encoding: .utf8)
        let list = try #require(text.firstMatch(of: #/probedSites\s*=\s*\[([^\]]*)\]/#), "probedSites not found")
        let probed = list.1.matches(of: #/"([a-z]+)"/#).map { String($0.1) }
        #expect(probed == NetworkTrap.sites, "UI test probes \(probed), the trap lists \(NetworkTrap.sites)")
    }
}
