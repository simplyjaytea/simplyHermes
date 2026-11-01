import Foundation
import Testing

@testable import HermesKit

@Suite struct BotSettingsTests {
    // MARK: - 1. Describe Decoding

    @Test func describeDecodingMapsAllSectionsAndMaintainsToolsetsPinnedFalse() throws {
        let json = #"""
            {
              "name": "ops",
              "description": "Ops bot",
              "soul": "You are Ops, a terse operations bot.",
              "model": {"provider": "custom", "default": "fake-model"},
              "skills": [
                {"name": "apple-notes", "enabled": true},
                {"name": "claude-code", "enabled": false}
              ],
              "toolsets": [
                {"name": "web", "label": "Web Search", "description": "Search web", "tool_count": 2, "enabled": true},
                {"name": "terminal", "label": "Terminal", "description": "Run commands", "tool_count": 1, "enabled": false}
              ],
              "toolsets_pinned": false,
              "mcp_servers": [
                {"name": "local-db", "enabled": true, "transport": "stdio"}
              ]
            }
            """#
        let describe = try JSONDecoder().decode(ProfilesDescribeResult.self, from: Data(json.utf8))
        #expect(describe.name == "ops")
        #expect(describe.description == "Ops bot")
        #expect(describe.soul == "You are Ops, a terse operations bot.")
        #expect(describe.model.provider == "custom")
        #expect(describe.model.defaultModel == "fake-model")
        #expect(describe.skills?.count == 2)
        #expect(describe.toolsets?.count == 2)
        #expect(describe.toolsetsPinned == false)
        #expect(describe.mcpServers?.count == 1)

        let draft = BotSettingsDraft(describe: describe, title: "Ops Chief", isPinned: true)
        #expect(draft.targetProfile == "ops")
        #expect(draft.title == "Ops Chief")
        #expect(draft.role == "Ops bot")
        #expect(draft.soul == "You are Ops, a terse operations bot.")
        #expect(draft.provider == "custom")
        #expect(draft.model == "fake-model")
        #expect(draft.isPinned)
        #expect(!draft.isHidden)
        #expect(!draft.toolsetsPinned)
        #expect(draft.skills.count == 2)
        #expect(draft.toolsets.count == 2)
        #expect(draft.mcpServers.count == 1)
        #expect(!draft.isDirty)
        #expect(draft.dirtySections.isEmpty)
    }

    // MARK: - 2. Dirty-Section Diff

    @Test func dirtySectionDiffCarriesOnlyChangedSections() {
        var draft = BotSettingsDraft(
            targetProfile: "ops",
            title: "Ops",
            role: "Role",
            provider: "anthropic",
            model: "claude-3-5",
            soul: "Soul text",
            skills: [BotSettingsSkillItem(name: "s1", enabled: true)],
            toolsets: [BotSettingsToolsetItem(name: "t1", enabled: true)],
            toolsetsPinned: false,
            mcpServers: [BotSettingsMcpServerItem(name: "m1", enabled: true)]
        )

        // Baseline is clean
        #expect(!draft.isDirty)
        #expect(draft.buildConfigureParams() == nil)

        // Change only soul
        draft.soul = "Updated soul text"
        #expect(draft.isDirty)
        #expect(draft.dirtySections == [.soul])

        let soulParams = draft.buildConfigureParams()
        #expect(soulParams != nil)
        #expect(soulParams?.profile == "ops")
        #expect(soulParams?.name == "ops")
        #expect(soulParams?.soul == "Updated soul text")
        #expect(soulParams?.description == nil)
        #expect(soulParams?.model == nil)
        #expect(soulParams?.disabledSkills == nil)
        #expect(soulParams?.enabledToolsets == nil)
        #expect(soulParams?.enabledMCPServers == nil)

        // Change role as well
        draft.role = "Updated role"
        #expect(draft.dirtySections == [.identity, .soul])
        let multiParams = draft.buildConfigureParams()
        #expect(multiParams?.description == "Updated role")
        #expect(multiParams?.soul == "Updated soul text")
        #expect(multiParams?.model == nil)
    }

    // MARK: - 3. Inverse Skills Complement

    @Test func togglingSkillsProducesFullDisabledSkillsComplement() {
        var draft = BotSettingsDraft(
            targetProfile: "ops",
            skills: [
                BotSettingsSkillItem(name: "apple-notes", enabled: true),
                BotSettingsSkillItem(name: "claude-code", enabled: true),
                BotSettingsSkillItem(name: "github", enabled: true),
            ]
        )

        #expect(!draft.isSkillsDirty)
        #expect(draft.enabledSkillsCount == 3)
        #expect(draft.totalSkillsCount == 3)

        // Toggle claude-code off
        draft.toggleSkill(named: "claude-code")
        #expect(draft.isSkillsDirty)
        #expect(draft.enabledSkillsCount == 2)

        let params1 = draft.buildConfigureParams()
        #expect(params1?.disabledSkills == ["claude-code"])

        // Also toggle github off
        draft.toggleSkill(named: "github")
        #expect(draft.enabledSkillsCount == 1)

        let params2 = draft.buildConfigureParams()
        // Must carry full complement of all disabled skills, not just the last toggled
        #expect(params2?.disabledSkills?.sorted() == ["claude-code", "github"].sorted())

        // Toggle claude-code back on
        draft.toggleSkill(named: "claude-code")
        #expect(draft.enabledSkillsCount == 2)
        let params3 = draft.buildConfigureParams()
        #expect(params3?.disabledSkills == ["github"])
    }

    @Test func filteredSkillsSupportsSearchQuery() {
        let draft = BotSettingsDraft(
            targetProfile: "ops",
            skills: [
                BotSettingsSkillItem(name: "apple-notes", enabled: true),
                BotSettingsSkillItem(name: "apple-reminders", enabled: true),
                BotSettingsSkillItem(name: "github", enabled: true),
            ]
        )

        #expect(draft.filteredSkills(matching: "").count == 3)
        #expect(draft.filteredSkills(matching: "apple").map(\.name) == ["apple-notes", "apple-reminders"])
        #expect(draft.filteredSkills(matching: "git").map(\.name) == ["github"])
        #expect(draft.filteredSkills(matching: "xyz").isEmpty)
    }

    // MARK: - 4. Toolset Full-List Semantics

    @Test func toolsetInheritanceCustomizationAndResetProduceFullEnabledList() {
        var draft = BotSettingsDraft(
            targetProfile: "ops",
            toolsets: [
                BotSettingsToolsetItem(name: "web", enabled: true),
                BotSettingsToolsetItem(name: "terminal", enabled: true),
                BotSettingsToolsetItem(name: "stt", enabled: false),
            ],
            toolsetsPinned: false
        )

        #expect(!draft.isToolsetsDirty)
        #expect(!draft.toolsetsPinned)

        // Explicit customization pins the toolsets
        draft.customizeToolsets()
        #expect(draft.toolsetsPinned)
        #expect(draft.isToolsetsDirty)

        let customParams = draft.buildConfigureParams()
        #expect(customParams?.enabledToolsets?.sorted() == ["terminal", "web"].sorted())

        // Toggling one toolset keeps full list semantics
        draft.toggleToolset(named: "terminal")
        let toggledParams = draft.buildConfigureParams()
        #expect(toggledParams?.enabledToolsets == ["web"])

        // Reset reverts toolset states to baseline and unpins
        draft.resetToolsets()
        #expect(!draft.toolsetsPinned)
        #expect(!draft.isToolsetsDirty)
        #expect(draft.toolsets.first { $0.name == "terminal" }?.enabled == true)
    }

    // MARK: - 5. Confirm Flow

    @Test func confirmFlowHandlesConfirmationRequiredAndSecondWrite() {
        let resultConfirm = ProfilesConfigureResult(
            ok: false,
            applied: ProfilesConfigureApplied(),
            confirmRequired: true,
            confirmMessage: "claude-3-opus costs more per token than default models."
        )

        let outcome = BotSettingsSaveOutcome.evaluate(
            result: resultConfirm,
            requestedSections: [.model]
        )

        #expect(!outcome.isCompleteSuccess)
        #expect(outcome.confirmRequired)
        #expect(outcome.confirmMessage == "claude-3-opus costs more per token than default models.")
        #expect(outcome.appliedSections.isEmpty)
        #expect(outcome.failedSections.isEmpty)

        // Build second write with confirmExpensiveModel = true
        var draft = BotSettingsDraft(targetProfile: "ops", provider: "anthropic", model: "claude-3-5")
        draft.model = "claude-3-opus"
        let confirmParams = draft.buildConfigureParams(confirmExpensiveModel: true)
        #expect(confirmParams?.confirmExpensiveModel == true)

        // Second write success
        let resultSuccess = ProfilesConfigureResult(
            ok: true,
            applied: ProfilesConfigureApplied(model: true)
        )
        let secondOutcome = BotSettingsSaveOutcome.evaluate(
            result: resultSuccess,
            requestedSections: [.model]
        )
        #expect(secondOutcome.isCompleteSuccess)
        #expect(!secondOutcome.confirmRequired)
        #expect(secondOutcome.appliedSections == [.model])
    }

    // MARK: - 6. Partial Failure Handling

    @Test func partialFailureMaintainsFailedValuesAndReportsSpecificSections() {
        var draft = BotSettingsDraft(
            targetProfile: "ops",
            provider: "anthropic",
            model: "claude-3-haiku",
            soul: "Initial SOUL"
        )
        draft.model = "claude-3-5"
        draft.soul = "Updated SOUL"

        let requested = draft.dirtySections
        #expect(requested == [.model, .soul])

        // Server saved soul, but refused model
        let result = ProfilesConfigureResult(
            ok: false,
            applied: ProfilesConfigureApplied(soul: true, model: false)
        )

        let outcome = BotSettingsSaveOutcome.evaluate(
            result: result,
            requestedSections: requested
        )

        #expect(!outcome.isCompleteSuccess)
        #expect(outcome.appliedSections == [.soul])
        #expect(outcome.failedSections == [.model])
        #expect(outcome.statusMessage.contains("Personality (SOUL) saved"))
        #expect(outcome.statusMessage.contains("Model & Provider could not be updated"))

        // Applying successful sections updates baseline for soul, but preserves model dirty state
        draft.applySuccessfulSections(outcome.appliedSections)
        #expect(!draft.isSoulDirty)
        #expect(draft.isModelDirty)
        #expect(draft.model == "claude-3-5")  // Failed value preserved for user to adjust
    }

    // MARK: - 7. Target-Profile Scoping

    @Test func targetProfileScopingPassesBothProfileAndNameOnAllCalls() async throws {
        let gateway = FakeBotGateway(
            [
                "profiles.describe": [
                    .json(#"{"name": "ops", "description": "Ops", "model": {"provider": "p", "default": "m"}}"#)
                ],
                "profiles.configure": [
                    .json(#"{"ok": true, "applied": {"soul": true}}"#)
                ],
                "model.options": [
                    .json(#"{"providers": [{"slug": "p", "name": "Provider", "models": ["m"]}]}"#)
                ],
            ], activeProfile: "default")

        let client = BotClient(gateway: gateway)
        let describe = try await client.describeProfile("ops")
        #expect(describe.name == "ops")

        var draft = BotSettingsDraft(describe: describe)
        draft.soul = "New soul"
        let params = try #require(draft.buildConfigureParams())
        let configResult = try await client.configureProfile(params)
        #expect(configResult.applied.soul == true)

        let options = try await client.modelOptions(profile: "ops")
        #expect(options.providers.first?.slug == "p")

        let calls = await gateway.calls
        let describeCall = calls.first { $0.method == "profiles.describe" }
        #expect(describeCall?.params?["profile"]?.stringValue == "ops")
        #expect(describeCall?.params?["name"]?.stringValue == "ops")

        let configureCall = calls.first { $0.method == "profiles.configure" }
        #expect(configureCall?.params?["profile"]?.stringValue == "ops")
        #expect(configureCall?.params?["name"]?.stringValue == "ops")

        let optionsCall = calls.first { $0.method == "model.options" }
        #expect(optionsCall?.params?["profile"]?.stringValue == "ops")
    }

    // MARK: - 8. Offline and Error Mapping

    @Test func errorMappingTranslatesOfflineAndRpcErrors() {
        struct OfflineError: LocalizedError {
            var errorDescription: String? { "The network connection was lost and is offline." }
        }
        let offlineMsg = BotSettingsError.message(for: OfflineError())
        #expect(offlineMsg == "The server is offline or unreachable. Check your connection.")

        let rpc4062 = BotSettingsError.message(for: RPCError(code: 4062, message: "duplicate profile"))
        #expect(rpc4062 == "A bot with that name already exists.")

        let rpc4115 = BotSettingsError.message(for: RPCError(code: 4115, message: "driver unavailable"))
        #expect(rpc4115 == "The server driver is unavailable. Try again later.")

        let conflictMsg = BotSettingsError.message(for: BotError.metaConflict("ops"))
        #expect(conflictMsg == "Someone else changed this bot at the same time. Try again.")

        let metaTooLargeMsg = BotSettingsError.message(for: BotError.metaTooLarge)
        #expect(metaTooLargeMsg == "Those settings are too large to save.")
    }

    // MARK: - 9. Validation Limits

    @Test func validationEnforcesLengthCapsAndCompleteness() {
        var draft = BotSettingsDraft(targetProfile: "ops")
        #expect(draft.isValid)

        // Title cap (100)
        draft.title = String(repeating: "A", count: 101)
        #expect(!draft.isValid)
        #expect(draft.problems == [.titleTooLong(100)])
        #expect(draft.problems.first?.userMessage == "Title cannot exceed 100 characters.")

        draft.title = "Valid Title"
        #expect(draft.isValid)

        // Role cap (500)
        draft.role = String(repeating: "R", count: 501)
        #expect(!draft.isValid)
        #expect(draft.problems == [.roleTooLong(500)])

        draft.role = "Valid Role"
        #expect(draft.isValid)

        // Soul cap (100,000)
        draft.soul = String(repeating: "S", count: 100_001)
        #expect(!draft.isValid)
        #expect(draft.problems == [.soulTooLong(100_000)])

        draft.soul = "Valid Soul"
        #expect(draft.isValid)

        // Model incomplete: provider without model
        draft.provider = "anthropic"
        draft.model = ""
        #expect(!draft.isValid)
        #expect(draft.problems == [.modelIncomplete])

        draft.model = "claude-3-5"
        #expect(draft.isValid)
    }

    // MARK: - 10. OpenRPC Contract Conformance

    @Test func configurePayloadContainsOnlyContractDefinedKeys() throws {
        let contractURL = FixtureFiles.directory.deletingLastPathComponent()
            .appendingPathComponent("docs/protocol/gateway-contract.openrpc.json")
        let rootData = try Data(contentsOf: contractURL)
        let rootObject = try #require(try JSONSerialization.jsonObject(with: rootData) as? [String: Any])
        let schemas = try #require((rootObject["components"] as? [String: Any])?["schemas"] as? [String: Any])
        let configureSchema = try #require(schemas["ProfilesConfigureParams"] as? [String: Any])

        #expect(configureSchema["additionalProperties"] as? Bool == false)
        let allowedProperties = Set(try #require((configureSchema["properties"] as? [String: Any])?.keys))

        // Ensure toolsets_pinned is NOT part of the contract schema
        #expect(!allowedProperties.contains("toolsets_pinned"))

        // Full params payload containing all properties
        let params = ProfilesConfigureParams(
            profile: "ops",
            name: "ops",
            soul: "Ops soul",
            description: "Ops description",
            model: "claude-3-5",
            provider: "anthropic",
            confirmExpensiveModel: true,
            disabledSkills: ["skill-1"],
            enabledToolsets: ["web", "terminal"],
            enabledMCPServers: ["mcp-1"]
        )

        let encodedData = try JSONEncoder().encode(params)
        let encodedDict = try #require(JSONSerialization.jsonObject(with: encodedData) as? [String: Any])

        // All encoded keys must be strictly within the contract schema
        for encodedKey in encodedDict.keys {
            #expect(allowedProperties.contains(encodedKey))
        }
        #expect(!encodedDict.keys.contains("toolsets_pinned"))

        // Customize toolsets produces enabled_toolsets within contract
        var draft = BotSettingsDraft(
            targetProfile: "ops",
            toolsets: [
                BotSettingsToolsetItem(name: "web", enabled: true),
                BotSettingsToolsetItem(name: "terminal", enabled: true),
            ],
            toolsetsPinned: false
        )
        draft.customizeToolsets()
        let customParams = try #require(draft.buildConfigureParams())
        let customData = try JSONEncoder().encode(customParams)
        let customDict = try #require(JSONSerialization.jsonObject(with: customData) as? [String: Any])
        for encodedKey in customDict.keys {
            #expect(allowedProperties.contains(encodedKey))
        }
        #expect(!customDict.keys.contains("toolsets_pinned"))

        // Reset toolsets reverts toolset customization without sending unsupported unpin field
        draft.resetToolsets()
        #expect(!draft.toolsetsPinned)
        #expect(!draft.isToolsetsDirty)
        #expect(draft.buildConfigureParams() == nil)
    }

    // MARK: - 11. Model & Gateway Save Flow Tests

    @Test func saveFlowIdentityOnlyDoesNotCallConfigureProfile() async throws {
        let gateway = FakeBotGateway([
            "profiles.list": [
                .json(botListing(revisions: #"{"hermes-bots": 1}"#))
            ],
            "profiles.configure": [
                .json(#"{"ok": true, "applied": {"ui_meta": true}}"#)
            ],
        ])
        let client = BotClient(gateway: gateway)
        let coordinator = BotSettingsCoordinator(client: client)

        var draft = BotSettingsDraft(
            targetProfile: "ops",
            title: "Original Title",
            role: "Operator"
        )
        draft.title = "Updated Title"
        draft.isPinned = true

        #expect(draft.isIdentityMetaDirty)
        #expect(!draft.isRoleDirty)
        #expect(!draft.hasConfigurePayload)

        let outcome = try await coordinator.save(draft: &draft)
        #expect(outcome == nil)
        #expect(!draft.isDirty)
        #expect(!draft.isIdentityMetaDirty)

        let calls = await gateway.calls
        let configureCalls = calls.filter { $0.method == "profiles.configure" }
        #expect(configureCalls.count == 1)
        let callParams = configureCalls.first?.params
        #expect(callParams?["ui_meta"]?["hermes-bots"]?["title"]?.stringValue == "Updated Title")
        #expect(callParams?["ui_meta"]?["hermes-bots"]?["pinned"]?.boolValue == true)
        #expect(callParams?["description"] == nil)
    }

    @Test func saveFlowWithIdentityAndConfigureAppliesBaselinesIndependently() async throws {
        let gateway = FakeBotGateway([
            "profiles.list": [
                .json(botListing(revisions: #"{"hermes-bots": 1}"#))
            ],
            "profiles.configure": [
                .json(#"{"ok": true, "applied": {"ui_meta": true}}"#),
                .json(#"{"ok": true, "applied": {"soul": true}}"#),
            ],
        ])
        let client = BotClient(gateway: gateway)
        let coordinator = BotSettingsCoordinator(client: client)

        var draft = BotSettingsDraft(
            targetProfile: "ops",
            title: "Original Title",
            soul: "Original Soul"
        )
        draft.title = "Updated Title"
        draft.soul = "Updated Soul"

        #expect(draft.isIdentityMetaDirty)
        #expect(draft.isSoulDirty)

        let outcome = try await coordinator.save(draft: &draft)
        let saveOutcome = try #require(outcome)
        #expect(saveOutcome.isCompleteSuccess)
        #expect(saveOutcome.appliedSections == [.soul])
        #expect(!draft.isDirty)
        #expect(!draft.isIdentityMetaDirty)
        #expect(!draft.isSoulDirty)

        let calls = await gateway.calls
        let configureCalls = calls.filter { $0.method == "profiles.configure" }
        #expect(configureCalls.count == 2)
    }

    @Test func saveFlowWithIdentitySuccessAndConfigurePartialFailurePreservesFailedSection() async throws {
        let gateway = FakeBotGateway([
            "profiles.list": [
                .json(botListing(revisions: #"{"hermes-bots": 1}"#))
            ],
            "profiles.configure": [
                .json(#"{"ok": true, "applied": {"ui_meta": true}}"#),
                .json(#"{"ok": false, "applied": {"soul": true, "model": false}}"#),
            ],
        ])
        let client = BotClient(gateway: gateway)
        let coordinator = BotSettingsCoordinator(client: client)

        var draft = BotSettingsDraft(
            targetProfile: "ops",
            title: "Original Title",
            provider: "anthropic",
            model: "claude-3-haiku",
            soul: "Original Soul"
        )
        draft.title = "Updated Title"
        draft.soul = "Updated Soul"
        draft.model = "claude-3-5"

        let outcome = try await coordinator.save(draft: &draft)
        let saveOutcome = try #require(outcome)
        #expect(!saveOutcome.isCompleteSuccess)
        #expect(saveOutcome.appliedSections == [.soul])
        #expect(saveOutcome.failedSections == [.model])

        // Identity and soul baseline updated, model remains dirty with failed value
        #expect(!draft.isIdentityMetaDirty)
        #expect(!draft.isSoulDirty)
        #expect(draft.isModelDirty)
        #expect(draft.model == "claude-3-5")
    }

    @Test func confirmExpensiveModelChangeFlowWithMultiSectionEvaluation() async throws {
        let gateway = FakeBotGateway([
            "profiles.configure": [
                .json(
                    #"{"ok": false, "confirm_required": true, "confirm_message": "Opus is expensive.", "applied": {"soul": true}}"#
                ),
                .json(#"{"ok": true, "applied": {"model": true}}"#),
            ]
        ])
        let client = BotClient(gateway: gateway)
        let coordinator = BotSettingsCoordinator(client: client)

        var draft = BotSettingsDraft(
            targetProfile: "ops",
            provider: "anthropic",
            model: "claude-3-5",
            soul: "Original Soul"
        )
        draft.soul = "Updated Soul"
        draft.model = "claude-3-opus"

        let firstOutcome = try await coordinator.save(draft: &draft)
        let initialOutcome = try #require(firstOutcome)
        #expect(initialOutcome.confirmRequired)
        #expect(initialOutcome.confirmMessage == "Opus is expensive.")
        #expect(initialOutcome.appliedSections == [.soul])

        // First save applied soul section immediately
        #expect(!draft.isSoulDirty)
        #expect(draft.isModelDirty)

        // Confirm second write sends only remaining dirty section with confirm_expensive_model: true
        let confirmOutcome = try await coordinator.confirmExpensiveModelChange(draft: &draft)
        #expect(confirmOutcome.isCompleteSuccess)
        #expect(confirmOutcome.appliedSections == [.model])
        #expect(!draft.isDirty)

        let calls = await gateway.calls
        let configureCalls = calls.filter { $0.method == "profiles.configure" }
        #expect(configureCalls.count == 2)
        let secondParams = configureCalls.last?.params
        #expect(secondParams?["confirm_expensive_model"]?.boolValue == true)
        #expect(secondParams?["soul"] == nil)
        #expect(secondParams?["model"]?.stringValue == "claude-3-opus")
    }

    // MARK: - 12. Identity Scoping and Payload Generation

    @Test func identityOnlyEditsDoNotProduceConfigurePayload() {
        var draft = BotSettingsDraft(
            targetProfile: "ops",
            title: "Ops",
            role: "Operator"
        )
        #expect(!draft.isDirty)
        #expect(!draft.isIdentityMetaDirty)
        #expect(!draft.hasConfigurePayload)
        #expect(draft.buildConfigureParams() == nil)

        // Only metadata (title, pinned, hidden, avatar) changed
        draft.title = "Ops Chief"
        draft.isPinned = true
        #expect(draft.isDirty)
        #expect(draft.isIdentityMetaDirty)
        #expect(!draft.isRoleDirty)
        #expect(!draft.hasConfigurePayload)
        #expect(draft.buildConfigureParams() == nil)  // No empty profiles.configure call!

        // When role changes, configure payload is required
        draft.role = "Lead Operator"
        #expect(draft.isRoleDirty)
        #expect(draft.hasConfigurePayload)
        let params = draft.buildConfigureParams()
        #expect(params?.description == "Lead Operator")

        // Applying successful identity metadata leaves only role dirty
        draft.applySuccessfulIdentityMeta()
        #expect(!draft.isIdentityMetaDirty)
        #expect(draft.isRoleDirty)
        #expect(draft.hasConfigurePayload)
    }

    // MARK: - 13. Confirm Flow With Multiple Sections

    @Test func confirmFlowEvaluatesAllSentSectionsAndKeepsFailedSectionsDirty() {
        var draft = BotSettingsDraft(
            targetProfile: "ops",
            provider: "anthropic",
            model: "claude-3-5",
            soul: "Terse assistant"
        )
        draft.model = "claude-3-opus"
        draft.soul = "Very verbose personality"
        #expect(draft.dirtySections == [.model, .soul])

        // First attempt returns confirm_required for model
        let confirmResult = ProfilesConfigureResult(
            ok: false,
            applied: ProfilesConfigureApplied(soul: true),
            confirmRequired: true,
            confirmMessage: "Opus is expensive."
        )
        let firstOutcome = BotSettingsSaveOutcome.evaluate(
            result: confirmResult,
            requestedSections: draft.dirtySections
        )
        #expect(firstOutcome.confirmRequired)
        #expect(!firstOutcome.isCompleteSuccess)
        #expect(firstOutcome.appliedSections == [.soul])

        draft.applySuccessfulSections(firstOutcome.appliedSections)
        #expect(!draft.isSoulDirty)
        #expect(draft.isModelDirty)

        // Second write with confirmExpensiveModel = true
        let secondParams = draft.buildConfigureParams(confirmExpensiveModel: true)
        #expect(secondParams?.confirmExpensiveModel == true)
        #expect(secondParams?.soul == nil)  // Already clean!
        #expect(secondParams?.model == "claude-3-opus")

        let secondResult = ProfilesConfigureResult(
            ok: true,
            applied: ProfilesConfigureApplied(model: true)
        )
        let secondOutcome = BotSettingsSaveOutcome.evaluate(
            result: secondResult,
            requestedSections: draft.dirtySections
        )
        #expect(secondOutcome.isCompleteSuccess)
        #expect(secondOutcome.appliedSections == [.model])

        draft.applySuccessfulSections(secondOutcome.appliedSections)
        #expect(!draft.isDirty)
    }

    // MARK: - 14. BotRosterEntry Memberwise Initializer

    @Test func botRosterEntryPublicInitializerConstructsWithDefaults() {
        let id = UUID()
        let entry = BotRosterEntry(
            connectionID: id,
            sourceLabel: "Gateway 1",
            profile: "ops",
            handle: "ops",
            title: "Ops Bot",
            monogram: "OB",
            tint: "accent"
        )
        #expect(entry.connectionID == id)
        #expect(entry.sourceLabel == "Gateway 1")
        #expect(entry.profile == "ops")
        #expect(entry.handle == "ops")
        #expect(entry.title == "Ops Bot")
        #expect(entry.monogram == "OB")
        #expect(entry.tint == "accent")
        #expect(entry.status == .ready)
        #expect(!entry.isPinned)
        #expect(!entry.isHidden)
        #expect(entry.role == nil)
        #expect(entry.avatar == nil)
    }
}
