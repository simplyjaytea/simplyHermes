import Foundation
import Testing

@testable import HermesKit

/// Answers each method from a script of replies. A method's last reply repeats once its script runs out.
private actor FakeBotGateway: BotGateway {
    enum Reply: Sendable {
        case json(String)
        case failure(RPCError)
    }

    struct Call: Sendable {
        let method: String
        let params: JSONValue?
    }

    private var scripts: [String: [Reply]]
    private(set) var calls: [Call] = []

    init(_ scripts: [String: [Reply]]) {
        self.scripts = scripts
    }

    func call<Value: Decodable & Sendable>(
        _ method: String, params: (any Encodable & Sendable)?, as type: Value.Type
    ) async throws -> Value {
        calls.append(Call(method: method, params: try params.map { try JSONValue(encoding: $0) }))
        guard let script = scripts[method], let reply = script.first else {
            throw RPCError(code: -32601, message: "no reply scripted for \(method)")
        }
        if script.count > 1 { scripts[method] = Array(script.dropFirst()) }
        switch reply {
        case .json(let text): return try JSONDecoder().decode(Value.self, from: Data(text.utf8))
        case .failure(let error): throw error
        }
    }
}

/// A `profiles.list` answer with one profile, carrying the given revisions and `ui_meta`.
private func listing(_ profile: String = "ops", revisions: String = "{}", uiMeta: String = "{}") -> String {
    #"""
    {"profiles": [{"name": "\#(profile)", "path": "/p/\#(profile)", "ui_meta": \#(uiMeta),
      "ui_meta_revisions": \#(revisions)}], "bot_mode_protocol": true, "install_id": "I1"}
    """#
}

private let conflict =
    #"{"ok": false, "applied": {"ui_meta": false, "ui_meta_conflicts": {"hermes-bots": {"expected": 1, "actual": 2}}}}"#
private let saved = #"{"ok": true, "applied": {"ui_meta": true}}"#

@Suite struct BotClientTests {
    @Test func namespaceWriteRereadsAndRetriesAfterAConflict() async throws {
        let gateway = FakeBotGateway([
            "profiles.list": [
                .json(listing(revisions: #"{"hermes-bots": 1}"#)),
                .json(listing(revisions: #"{"hermes-bots": 2}"#)),
            ],
            "profiles.configure": [.json(conflict), .json(saved)],
        ])
        try await BotClient(gateway: gateway).updateNamespace(
            profile: "ops", namespace: BotMetaNamespace.desktop
        ) { $0.pinned = true }
        let writes = await gateway.calls.filter { $0.method == "profiles.configure" }.compactMap(\.params)
        #expect(writes.count == 2)
        #expect(writes.last?["ui_meta_expected_revisions"]?["hermes-bots"]?.intValue == 2)
        #expect(writes.last?["ui_meta"]?["hermes-bots"]?["pinned"]?.boolValue == true)
    }

    @Test func namespaceWriteGivesUpAfterMaxAttempts() async throws {
        let gateway = FakeBotGateway([
            "profiles.list": [.json(listing(revisions: #"{"hermes-bots": 1}"#))],
            "profiles.configure": [.json(conflict)],
        ])
        await #expect(throws: BotError.metaConflict("ops")) {
            try await BotClient(gateway: gateway).updateNamespace(
                profile: "ops", namespace: BotMetaNamespace.desktop
            ) { $0.pinned = true }
        }
        let writes = await gateway.calls.filter { $0.method == "profiles.configure" }.count
        #expect(writes == BotClient.maxAttempts)
    }

    @Test func writeWithoutAnAcknowledgementIsAnError() async throws {
        let gateway = FakeBotGateway([
            "profiles.list": [.json(listing())],
            "profiles.configure": [.json(#"{"ok": true, "applied": {}}"#)],
        ])
        await #expect(throws: BotError.metaNotSaved("ops")) {
            try await BotClient(gateway: gateway).updateNamespace(
                profile: "ops", namespace: BotMetaNamespace.desktop
            ) { $0.pinned = true }
        }
    }

    @Test func oversizedNamespaceIsRefusedBeforeAnyWrite() async throws {
        let gateway = FakeBotGateway(["profiles.list": [.json(listing())]])
        let big = String(repeating: "x", count: BotMetaNamespace.maxPayloadBytes)
        await #expect(throws: BotError.metaTooLarge) {
            try await BotClient(gateway: gateway).updateNamespace(
                profile: "ops", namespace: BotMetaNamespace.app
            ) { $0.setValue("blob", .string(big)) }
        }
        let methods = await gateway.calls.map(\.method)
        #expect(methods == ["profiles.list"])
    }

    @Test func unknownProfileIsReportedBeforeAnyWrite() async throws {
        let gateway = FakeBotGateway(["profiles.list": [.json(listing("other"))]])
        await #expect(throws: BotError.profileNotFound("ops")) {
            try await BotClient(gateway: gateway).updateNamespace(
                profile: "ops", namespace: BotMetaNamespace.desktop
            ) { $0.pinned = true }
        }
    }

    @Test func botChatLookupFailsClosedWhenTheRosterKnowsOne() async throws {
        let gateway = FakeBotGateway(["session.list": [.json(#"{"sessions": []}"#)]])
        let client = BotClient(gateway: gateway)
        let known = try await client.findBotChat(profile: "ops", rosterKnowsChat: true)
        let unknown = try await client.findBotChat(profile: "ops", rosterKnowsChat: false)
        #expect(known == .inconsistent)
        #expect(unknown == .none)
        let params = await gateway.calls.first?.params
        #expect(params?["title"]?.stringValue == "Bot Chat")
        #expect(params?["include_hidden"]?.boolValue == true)
    }

    @Test func createBotChatReturnsTheStoredIDOnSuccess() async throws {
        let gateway = FakeBotGateway([
            "session.create": [.json(#"{"session_id": "live1", "stored_session_id": "stored1"}"#)],
            "session.title": [.json(#"{"ok": true}"#)],
        ])
        let openID = try await BotClient(gateway: gateway).createBotChat(profile: "ops")
        #expect(openID == "stored1")
        let create = await gateway.calls.first { $0.method == "session.create" }?.params
        #expect(create?["hidden"]?.boolValue == true)
        #expect(create?["follow_profile_config"]?.boolValue == true)
    }

    @Test func createBotChatAdoptsTheChatAnotherWriterMade() async throws {
        let gateway = FakeBotGateway([
            "session.create": [.json(#"{"session_id": "live2", "stored_session_id": null}"#)],
            "session.title": [.failure(RPCError(code: 4022, message: "title taken"))],
            "session.list": [
                .json(#"{"sessions": [{"id": "stored9", "resolved_id": "live9", "root_title": "Bot Chat"}]}"#)
            ],
        ])
        let openID = try await BotClient(gateway: gateway).createBotChat(profile: "ops")
        #expect(openID == "live9")
    }

    @Test func createBotChatRefusesWhenTheTitleIsTakenButNotFound() async throws {
        let gateway = FakeBotGateway([
            "session.create": [.json(#"{"session_id": "live3"}"#)],
            "session.title": [.failure(RPCError(code: 4022, message: "title taken"))],
            "session.list": [.json(#"{"sessions": []}"#)],
        ])
        await #expect(throws: BotError.chatInconsistent("ops")) {
            try await BotClient(gateway: gateway).createBotChat(profile: "ops")
        }
    }

    @Test func createAgentWritesTitleLookAndAvatar() async throws {
        let gateway = FakeBotGateway([
            "profiles.create": [.json(#"{"ok": true, "name": "ops-two", "path": "/p/ops-two"}"#)],
            "profiles.list": [.json(listing("ops-two"))],
            "profiles.configure": [.json(saved)],
        ])
        let draft = NewAgentDraft(
            name: "Ops Two", title: "Ops", roleDescription: "Runs deploys", avatar: .emoji("🦉"))
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let created = try await BotClient(gateway: gateway).createAgent(
            draft, existingProfiles: ["default", "ops"], now: now)
        #expect(created == BotClient.CreatedAgent(profile: "ops-two", lookSaved: true))

        let writes = await gateway.calls.filter { $0.method == "profiles.configure" }.compactMap(\.params)
        #expect(writes.count == 2)
        #expect(writes[0]["ui_meta"]?["hermes-bots"]?["title"]?.stringValue == "Ops")
        #expect(writes[0]["ui_meta"]?["hermes-bots"]?["created"]?.intValue == 1_800_000_000_000)
        #expect(writes[0]["ui_meta"]?["hermes-bots"]?["shape"]?.stringValue == "blobatar")
        #expect(writes[1]["ui_meta"]?["simplyhermes"]?["avatar"]?["value"]?.stringValue == "🦉")
    }

    @Test func createAgentKeepsTheProfileWhenTheLookDoesNotSave() async throws {
        let gateway = FakeBotGateway([
            "profiles.create": [.json(#"{"ok": true, "name": "ops-two", "path": "/p/ops-two"}"#)],
            "profiles.list": [.json(listing("ops-two"))],
            "profiles.configure": [.json(#"{"ok": true, "applied": {}}"#)],
        ])
        let created = try await BotClient(gateway: gateway).createAgent(
            NewAgentDraft(name: "Ops Two"), existingProfiles: ["ops"])
        #expect(created == BotClient.CreatedAgent(profile: "ops-two", lookSaved: false))
    }

    @Test func createAgentRefusesATakenNameWithoutCalling() async throws {
        let gateway = FakeBotGateway([:])
        await #expect(throws: BotError.invalidDraft([.nameTaken])) {
            try await BotClient(gateway: gateway).createAgent(
                NewAgentDraft(name: "ops"), existingProfiles: ["ops"])
        }
        let methods = await gateway.calls.map(\.method)
        #expect(methods.isEmpty)
    }

    @Test func richRosterMapsLiveFieldsAndLook() async throws {
        let body = #"""
            {"profiles": [
              {"name": "default", "path": "/d", "is_default": true,
               "canonical_session": {"resolved_id": "c1", "last_active": 100.5, "preview": "hi"}},
              {"name": "ops", "path": "/o", "is_default": false, "display_name": "",
               "ui_meta": {"hermes-bots": {"title": "Ops Bot", "pinned": true},
                           "simplyhermes": {"avatar": {"kind": "emoji", "value": "🦉"}}},
               "worker_session": {"last_active": 200.25}, "last_session": {"last_active": 150.0}}
            ], "bot_mode_protocol": true, "install_id": "I1"}
            """#
        let gateway = FakeBotGateway(["profiles.list": [.json(body)]])
        let roster = try await BotClient(gateway: gateway).richRoster()
        #expect(roster.installID == "I1")
        #expect(roster.botModeProtocol)

        let defaultRow = try #require(roster.rows.first { $0.profile == "default" })
        #expect(defaultRow.canonicalSessionID == "c1")
        #expect(defaultRow.lastActive == 100.5)
        #expect(defaultRow.preview == "hi")

        let ops = try #require(roster.rows.first { $0.profile == "ops" })
        #expect(ops.meta.title == "Ops Bot")
        #expect(ops.meta.pinned)
        #expect(ops.appLook.avatar == .emoji("🦉"))
        #expect(ops.workerActiveAt == 200.25)
        #expect(ops.lastActive == 150)
    }

    @Test func restRowsReadThinFieldsAndAddTheDefaultProfile() throws {
        let list = try botRESTDecoder().decode(
            ProfileList.self,
            from: Data(
                #"{"profiles": [{"name": "ops", "is_default": false, "bot_title": "Ops Bot", "display_name": "", "model": "m"}]}"#
                    .utf8))
        let rows = BotClient.restRows(list.profiles)
        #expect(rows.map(\.profile) == ["default", "ops"])
        #expect(rows[0].isDefault)
        #expect(rows[1].backendTitle == "Ops Bot")
        #expect(rows[1].displayName == nil)
        #expect(rows[1].model == "m")
    }

    @Test func statusReportsTheInstallIDFromItsSnakeCaseKey() throws {
        let status = try botRESTDecoder().decode(
            ServerStatus.self, from: Data(#"{"install_id": "I9", "version": "2026.9.24"}"#.utf8))
        #expect(status.installId == "I9")
    }

    @Test func roleIsWrittenAsTheProfileDescription() async throws {
        let gateway = FakeBotGateway([
            "profiles.configure": [.json(#"{"ok": true, "applied": {"description": true}}"#)]
        ])
        try await BotClient(gateway: gateway).setRole(profile: "ops", role: "Runs deploys")
        let params = await gateway.calls.first?.params
        #expect(params?["name"]?.stringValue == "ops")
        #expect(params?["description"]?.stringValue == "Runs deploys")
    }

    @Test func unacknowledgedRoleIsAnError() async throws {
        let gateway = FakeBotGateway([
            "profiles.configure": [.json(#"{"ok": true, "applied": {}}"#)]
        ])
        await #expect(throws: BotError.roleNotSaved("ops")) {
            try await BotClient(gateway: gateway).setRole(profile: "ops", role: "Runs deploys")
        }
    }
}
