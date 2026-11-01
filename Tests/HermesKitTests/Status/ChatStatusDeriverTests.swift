import Foundation
import Testing

@testable import HermesKit

struct ChatStatusDeriverTests {
    private static let serverChat = ChatBackend.server(
        connectionID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, profile: nil, sessionID: "s1")
    private static let localChat = ChatBackend.local(
        chatID: UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!)

    private static let gemmaModel = OnDeviceModelCatalog.standard.models[0]
    private static let gemma = ModelIdentity.downloaded(id: gemmaModel.id, displayName: gemmaModel.displayName)
    private static let noModel = LocalModelStatus.noModel

    /// One row of the status table: the facts, and the status they must produce.
    private struct Row {
        let name: String
        let backend: ChatBackend
        let phase: ConnectionPhase?
        let path: NetworkPath
        let local: LocalModelStatus
        let expected: ChatStatus
    }

    private static func status(_ pill: PillState, canSend: Bool, _ sendPath: SendPath) -> ChatStatus {
        ChatStatus(pill: pill, canSend: canSend, sendPath: sendPath)
    }

    /// Every row the status can take, one per case that matters. The server rows ignore the local model; the local
    /// rows ignore the connection and the network.
    private static let rows: [Row] = [
        // No network: a server chat is unreachable at once, whatever the connection last said.
        Row(
            name: "no network + checkingServer is unreachable immediately", backend: serverChat,
            phase: .checkingServer, path: .unsatisfied, local: noModel,
            expected: status(.unreachable, canSend: true, .askUser)),
        Row(
            name: "no network + no phase yet", backend: serverChat, phase: nil, path: .unsatisfied, local: noModel,
            expected: status(.unreachable, canSend: true, .askUser)),
        Row(
            name: "no network + idle", backend: serverChat, phase: .idle, path: .unsatisfied, local: noModel,
            expected: status(.unreachable, canSend: true, .askUser)),
        Row(
            name: "no network + unlocking", backend: serverChat, phase: .unlocking, path: .unsatisfied, local: noModel,
            expected: status(.unreachable, canSend: true, .askUser)),
        Row(
            name: "no network + openingTunnel", backend: serverChat, phase: .openingTunnel, path: .unsatisfied,
            local: noModel, expected: status(.unreachable, canSend: true, .askUser)),
        Row(
            name: "no network + connecting", backend: serverChat, phase: .connecting, path: .unsatisfied,
            local: noModel, expected: status(.unreachable, canSend: true, .askUser)),
        Row(
            name: "no network + connected is stale", backend: serverChat, phase: .connected(ServerSummary()),
            path: .unsatisfied, local: noModel, expected: status(.unreachable, canSend: true, .askUser)),
        Row(
            name: "no network + reconnecting", backend: serverChat, phase: .reconnecting(attempt: 2),
            path: .unsatisfied, local: noModel, expected: status(.unreachable, canSend: true, .askUser)),
        Row(
            name: "no network + sign-in still needed", backend: serverChat, phase: .signInRequired,
            path: .unsatisfied, local: noModel, expected: status(.needsSignIn, canSend: false, .askUser)),
        Row(
            name: "no network + failed unreachable", backend: serverChat, phase: .failed(.unreachable("timeout")),
            path: .unsatisfied, local: noModel, expected: status(.unreachable, canSend: true, .askUser)),

        // Network present or unknown: the connection's own phase decides.
        Row(
            name: "unknown path + no phase is connecting", backend: serverChat, phase: nil, path: .unknown,
            local: noModel, expected: status(.connecting, canSend: true, .hold)),
        Row(
            name: "satisfied + no phase is connecting", backend: serverChat, phase: nil, path: .satisfied,
            local: noModel, expected: status(.connecting, canSend: true, .hold)),
        Row(
            name: "satisfied + idle is connecting", backend: serverChat, phase: .idle, path: .satisfied,
            local: noModel, expected: status(.connecting, canSend: true, .hold)),
        Row(
            name: "satisfied + unlocking is connecting", backend: serverChat, phase: .unlocking, path: .satisfied,
            local: noModel, expected: status(.connecting, canSend: true, .hold)),
        Row(
            name: "satisfied + openingTunnel is connecting", backend: serverChat, phase: .openingTunnel,
            path: .satisfied, local: noModel, expected: status(.connecting, canSend: true, .hold)),
        Row(
            name: "satisfied + checkingServer is connecting", backend: serverChat, phase: .checkingServer,
            path: .satisfied, local: noModel, expected: status(.connecting, canSend: true, .hold)),
        Row(
            name: "satisfied + connecting is connecting", backend: serverChat, phase: .connecting, path: .satisfied,
            local: noModel, expected: status(.connecting, canSend: true, .hold)),
        Row(
            name: "satisfied + connected sends to the server", backend: serverChat,
            phase: .connected(ServerSummary()), path: .satisfied, local: noModel,
            expected: status(.connected, canSend: true, .server)),
        Row(
            name: "unknown + connected sends to the server", backend: serverChat,
            phase: .connected(ServerSummary()), path: .unknown, local: noModel,
            expected: status(.connected, canSend: true, .server)),
        Row(
            name: "satisfied + reconnecting(1) holds", backend: serverChat, phase: .reconnecting(attempt: 1),
            path: .satisfied, local: noModel, expected: status(.reconnecting, canSend: true, .hold)),
        Row(
            name: "unknown + reconnecting(5) holds", backend: serverChat, phase: .reconnecting(attempt: 5),
            path: .unknown, local: noModel, expected: status(.reconnecting, canSend: true, .hold)),
        Row(
            name: "satisfied + signInRequired", backend: serverChat, phase: .signInRequired, path: .satisfied,
            local: noModel, expected: status(.needsSignIn, canSend: false, .askUser)),
        Row(
            name: "satisfied + updateRequired", backend: serverChat, phase: .updateRequired(found: "0.1"),
            path: .satisfied, local: noModel, expected: status(.needsSignIn, canSend: false, .askUser)),
        Row(
            name: "failed unreachable", backend: serverChat, phase: .failed(.unreachable("timeout")),
            path: .satisfied, local: noModel, expected: status(.unreachable, canSend: true, .askUser)),
        Row(
            name: "failed notHermes", backend: serverChat, phase: .failed(.notHermes), path: .satisfied,
            local: noModel, expected: status(.unreachable, canSend: true, .askUser)),
        Row(
            name: "failed signInRequired", backend: serverChat,
            phase: .failed(.signInRequired(providers: ["github"])), path: .satisfied, local: noModel,
            expected: status(.needsSignIn, canSend: false, .askUser)),
        Row(
            name: "failed wrongCredentials", backend: serverChat, phase: .failed(.wrongCredentials),
            path: .satisfied, local: noModel, expected: status(.needsSignIn, canSend: false, .askUser)),
        Row(
            name: "failed missingSecret", backend: serverChat, phase: .failed(.missingSecret), path: .satisfied,
            local: noModel, expected: status(.needsSignIn, canSend: false, .askUser)),
        Row(
            name: "failed rateLimited", backend: serverChat, phase: .failed(.rateLimited(retryAfter: 60)),
            path: .satisfied, local: noModel, expected: status(.unreachable, canSend: true, .askUser)),
        Row(
            name: "failed server 502", backend: serverChat, phase: .failed(.server(status: 502, detail: nil)),
            path: .satisfied, local: noModel, expected: status(.unreachable, canSend: true, .askUser)),
        Row(
            name: "failed hostKeyRejected", backend: serverChat, phase: .failed(.hostKeyRejected),
            path: .satisfied, local: noModel, expected: status(.needsSignIn, canSend: false, .askUser)),
        Row(
            name: "failed hostKeyChanged", backend: serverChat,
            phase: .failed(.hostKeyChanged(expected: "a", actual: "b")), path: .satisfied, local: noModel,
            expected: status(.needsSignIn, canSend: false, .askUser)),
        Row(
            name: "failed ssh", backend: serverChat, phase: .failed(.ssh("tunnel closed")), path: .satisfied,
            local: noModel, expected: status(.unreachable, canSend: true, .askUser)),
        Row(
            name: "failed webSocket", backend: serverChat, phase: .failed(.webSocket("closed")), path: .satisfied,
            local: noModel, expected: status(.unreachable, canSend: true, .askUser)),
        Row(
            name: "failed invalidForm", backend: serverChat, phase: .failed(.invalidForm("no host")),
            path: .satisfied, local: noModel, expected: status(.needsSignIn, canSend: false, .askUser)),
        Row(
            name: "failed serverTooOld", backend: serverChat, phase: .failed(.serverTooOld(found: "0.1")),
            path: .satisfied, local: noModel, expected: status(.needsSignIn, canSend: false, .askUser)),

        // A server chat never takes its answer from the local model, even when the model is ready.
        Row(
            name: "connected ignores a ready local model", backend: serverChat, phase: .connected(ServerSummary()),
            path: .satisfied, local: .ready(answeredBy: .apple), expected: status(.connected, canSend: true, .server)),
        Row(
            name: "unreachable never falls back to a ready local model", backend: serverChat,
            phase: .failed(.unreachable("x")), path: .satisfied, local: .ready(answeredBy: .apple),
            expected: status(.unreachable, canSend: true, .askUser)),
        Row(
            name: "no network never falls back to a ready local model", backend: serverChat,
            phase: .connected(ServerSummary()), path: .unsatisfied, local: .ready(answeredBy: .apple),
            expected: status(.unreachable, canSend: true, .askUser)),

        // Local chats: only the on-device model matters.
        Row(
            name: "local + features off", backend: localChat, phase: nil, path: .unknown, local: .off,
            expected: status(.localOff, canSend: false, .hold)),
        Row(
            name: "local + no model, offline", backend: localChat, phase: nil, path: .unsatisfied, local: noModel,
            expected: status(.localNoModel, canSend: false, .hold)),
        Row(
            name: "local + downloading", backend: localChat, phase: nil, path: .satisfied,
            local: .downloading(progress: 0.4), expected: status(.localNoModel, canSend: false, .hold)),
        Row(
            name: "local + verifying", backend: localChat, phase: nil, path: .satisfied, local: .verifying,
            expected: status(.localNoModel, canSend: false, .hold)),
        Row(
            name: "local + model chosen, not loaded", backend: localChat, phase: nil, path: .satisfied,
            local: .notLoaded(gemmaModel), expected: status(.localReady(gemma), canSend: true, .local(gemma))),
        Row(
            name: "local + loading", backend: localChat, phase: nil, path: .satisfied, local: .loading(gemmaModel),
            expected: status(.localLoading(gemma), canSend: true, .hold)),
        Row(
            name: "local + Apple ready", backend: localChat, phase: nil, path: .satisfied,
            local: .ready(answeredBy: .apple),
            expected: status(.localReady(.apple), canSend: true, .local(.apple))),
        Row(
            name: "local + downloaded ready", backend: localChat, phase: nil, path: .satisfied,
            local: .ready(answeredBy: gemma), expected: status(.localReady(gemma), canSend: true, .local(gemma))),
        Row(
            name: "local + failed for memory", backend: localChat, phase: nil, path: .satisfied,
            local: .failed(gemma, reason: .notEnoughMemory(needed: 3_000_000_000, available: 2_000_000_000)),
            expected: status(
                .localFailed(gemma, reason: .notEnoughMemory(needed: 3_000_000_000, available: 2_000_000_000)),
                canSend: true, .hold)),
        Row(
            name: "local + Apple runtime missing", backend: localChat, phase: nil, path: .satisfied,
            local: .failed(.apple, reason: .runtimeUnavailable),
            expected: status(.localFailed(.apple, reason: .runtimeUnavailable), canSend: true, .hold)),
        Row(
            name: "local + load error", backend: localChat, phase: nil, path: .satisfied,
            local: .failed(gemma, reason: .loadError("corrupt weights")),
            expected: status(.localFailed(gemma, reason: .loadError("corrupt weights")), canSend: true, .hold)),
        Row(
            name: "local ignores an unreachable server", backend: localChat, phase: .failed(.unreachable("x")),
            path: .unsatisfied, local: .ready(answeredBy: gemma),
            expected: status(.localReady(gemma), canSend: true, .local(gemma))),
        Row(
            name: "local ignores a connected server", backend: localChat, phase: .connected(ServerSummary()),
            path: .satisfied, local: .loading(gemmaModel), expected: status(.localLoading(gemma), canSend: true, .hold)),
        Row(
            name: "local + features off with a server connected", backend: localChat,
            phase: .connected(ServerSummary()), path: .satisfied, local: .off,
            expected: status(.localOff, canSend: false, .hold)),
    ]

    @Test func theStatusTableMatchesTheRules() {
        #expect(Self.rows.count >= 40)
        for row in Self.rows {
            let actual = ChatStatusDeriver.derive(
                backend: row.backend, phase: row.phase, path: row.path, local: row.local)
            #expect(actual == row.expected, "\(row.name)")
        }
    }

    @Test func noServerIsItsOwnStatus() {
        #expect(ChatStatusDeriver.noServer == Self.status(.noServer, canSend: false, .askUser))
    }

    // MARK: - Invariants over every combination

    private static let phases: [ConnectionPhase?] = [
        nil, .idle, .unlocking, .openingTunnel, .checkingServer, .connecting, .connected(ServerSummary()),
        .reconnecting(attempt: 1), .signInRequired, .updateRequired(found: "0.1"),
        .failed(.unreachable("x")), .failed(.notHermes), .failed(.signInRequired(providers: [])),
        .failed(.wrongCredentials), .failed(.rateLimited(retryAfter: nil)), .failed(.server(status: 500, detail: nil)),
        .failed(.missingSecret), .failed(.hostKeyRejected), .failed(.hostKeyChanged(expected: "a", actual: "b")),
        .failed(.ssh("x")), .failed(.invalidForm("x")), .failed(.webSocket("x")), .failed(.serverTooOld(found: "x")),
    ]

    private static let paths: [NetworkPath] = [.unknown, .satisfied, .unsatisfied]

    private static let locals: [LocalModelStatus] = [
        .off, .noModel, .downloading(progress: 0.5), .verifying, .notLoaded(gemmaModel), .loading(gemmaModel),
        .ready(answeredBy: .apple), .ready(answeredBy: gemma), .failed(gemma, reason: .runtimeUnavailable),
    ]

    @Test func aServerChatNeverGetsALocalSendPath() {
        for phase in Self.phases {
            for path in Self.paths {
                for local in Self.locals {
                    let result = ChatStatusDeriver.derive(
                        backend: Self.serverChat, phase: phase, path: path, local: local)
                    if case .local = result.sendPath {
                        Issue.record("server chat answered locally: phase \(String(describing: phase)), \(path)")
                    }
                }
            }
        }
    }

    @Test func aLocalChatNeverReachesTheServer() {
        for phase in Self.phases {
            for path in Self.paths {
                for local in Self.locals {
                    let result = ChatStatusDeriver.derive(
                        backend: Self.localChat, phase: phase, path: path, local: local)
                    #expect(result.sendPath != .server)
                    #expect(result.sendPath != .askUser)
                }
            }
        }
    }

    @Test func aServerOutageAlwaysAsksTheUser() {
        for local in Self.locals {
            let result = ChatStatusDeriver.derive(
                backend: Self.serverChat, phase: .failed(.unreachable("x")), path: .satisfied, local: local)
            #expect(result == Self.status(.unreachable, canSend: true, .askUser))
        }
    }
}
