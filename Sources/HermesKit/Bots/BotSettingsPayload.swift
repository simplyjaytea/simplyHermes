import Foundation

/// The distinct configurable sections of a bot profile (WP-42 contract, plan PR B).
public enum BotSettingsSection: String, Sendable, CaseIterable, Hashable {
    case identity
    case model
    case soul
    case skills
    case toolsets
    case mcp

    public var displayName: String {
        switch self {
        case .identity: return "Identity"
        case .model: return "Model & Provider"
        case .soul: return "Personality (SOUL)"
        case .skills: return "Skills"
        case .toolsets: return "Toolsets"
        case .mcp: return "MCP Servers"
        }
    }
}

/// A skill entry in the bot settings editor.
public struct BotSettingsSkillItem: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public var name: String
    public var enabled: Bool

    public init(name: String, enabled: Bool) {
        self.name = name
        self.enabled = enabled
    }
}

/// A toolset entry in the bot settings editor.
public struct BotSettingsToolsetItem: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public var name: String
    public var enabled: Bool
    public var label: String?
    public var description: String?
    public var toolCount: Int?

    public init(name: String, enabled: Bool, label: String? = nil, description: String? = nil, toolCount: Int? = nil) {
        self.name = name
        self.enabled = enabled
        self.label = label
        self.description = description
        self.toolCount = toolCount
    }
}

/// An MCP server entry in the bot settings editor.
public struct BotSettingsMcpServerItem: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public var name: String
    public var enabled: Bool
    public var transport: String?

    public init(name: String, enabled: Bool, transport: String? = nil) {
        self.name = name
        self.enabled = enabled
        self.transport = transport
    }
}

/// Issues that block saving bot settings.
public enum BotSettingsProblem: Sendable, Equatable {
    case titleTooLong(Int)
    case roleTooLong(Int)
    case soulTooLong(Int)
    case modelIncomplete

    public var userMessage: String {
        switch self {
        case .titleTooLong(let max):
            return "Title cannot exceed \(max) characters."
        case .roleTooLong(let max):
            return "Role description cannot exceed \(max) characters."
        case .soulTooLong(let max):
            return "SOUL text cannot exceed \(max) characters."
        case .modelIncomplete:
            return "Set both the provider and the model, or neither."
        }
    }
}

/// Editable draft state for `BotSettingsScreen` with baseline snapshot tracking and dirty section diffing.
/// Note: Metadata payload size is guarded at save time by `BotClient.updateNamespace` enforcing
/// `BotMetaNamespace.maxPayloadBytes` (64 KB) and throwing `BotError.metaTooLarge`.
public struct BotSettingsDraft: Sendable, Equatable {
    public static let maxTitleLength = 100
    public static let maxRoleLength = 500
    public static let maxSoulLength = 100_000

    public var targetProfile: String

    // Section 1: Identity
    public var title: String
    public var role: String
    public var avatar: BotAvatar?
    public var isPinned: Bool
    public var isHidden: Bool

    // Section 2: Model & Provider
    public var provider: String
    public var model: String

    // Section 3: Soul
    public var soul: String

    // Section 4: Skills
    public var skills: [BotSettingsSkillItem]

    // Section 5: Toolsets
    public var toolsets: [BotSettingsToolsetItem]
    public var toolsetsPinned: Bool

    // Section 6: MCP Servers
    public var mcpServers: [BotSettingsMcpServerItem]

    // Baselines for dirty tracking
    private var baselineTitle: String
    private var baselineRole: String
    private var baselineAvatar: BotAvatar?
    private var baselineIsPinned: Bool
    private var baselineIsHidden: Bool
    private var baselineProvider: String
    private var baselineModel: String
    private var baselineSoul: String
    private var baselineSkills: [String: Bool]
    private var baselineToolsets: [String: Bool]
    private var baselineToolsetsPinned: Bool
    private var baselineMcpServers: [String: Bool]

    /// Initializes from a `profiles.describe` result and optional initial identity metadata.
    public init(
        describe: ProfilesDescribeResult,
        title: String? = nil,
        role: String? = nil,
        avatar: BotAvatar? = nil,
        isPinned: Bool = false,
        isHidden: Bool = false
    ) {
        targetProfile = describe.name

        let initTitle = title ?? ""
        let initRole = role ?? describe.description ?? ""
        let initAvatar = avatar
        let initPinned = isPinned
        let initHidden = isHidden

        self.title = initTitle
        self.role = initRole
        self.avatar = initAvatar
        self.isPinned = initPinned
        self.isHidden = initHidden

        baselineTitle = initTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        baselineRole = initRole.trimmingCharacters(in: .whitespacesAndNewlines)
        baselineAvatar = initAvatar
        baselineIsPinned = initPinned
        baselineIsHidden = initHidden

        let initProvider = describe.model.provider
        let initModel = describe.model.defaultModel
        self.provider = initProvider
        self.model = initModel
        baselineProvider = initProvider.trimmingCharacters(in: .whitespacesAndNewlines)
        baselineModel = initModel.trimmingCharacters(in: .whitespacesAndNewlines)

        let initSoul = describe.soul ?? ""
        self.soul = initSoul
        baselineSoul = initSoul.trimmingCharacters(in: .whitespacesAndNewlines)

        let skillItems = (describe.skills ?? []).map {
            BotSettingsSkillItem(name: $0.name, enabled: $0.enabled ?? true)
        }
        self.skills = skillItems
        baselineSkills = Dictionary(uniqueKeysWithValues: skillItems.map { ($0.name, $0.enabled) })

        let toolsetItems = (describe.toolsets ?? []).map {
            BotSettingsToolsetItem(
                name: $0.name,
                enabled: $0.enabled ?? true,
                label: $0.label,
                description: $0.description,
                toolCount: $0.toolCount
            )
        }
        self.toolsets = toolsetItems
        let initPinnedToolsets = describe.toolsetsPinned ?? false
        self.toolsetsPinned = initPinnedToolsets
        baselineToolsets = Dictionary(uniqueKeysWithValues: toolsetItems.map { ($0.name, $0.enabled) })
        baselineToolsetsPinned = initPinnedToolsets

        let mcpItems = (describe.mcpServers ?? []).map {
            BotSettingsMcpServerItem(name: $0.name, enabled: $0.enabled ?? true, transport: $0.transport)
        }
        self.mcpServers = mcpItems
        baselineMcpServers = Dictionary(uniqueKeysWithValues: mcpItems.map { ($0.name, $0.enabled) })
    }

    /// Explicit initializer for testing and programmatic initialization.
    public init(
        targetProfile: String,
        title: String = "",
        role: String = "",
        avatar: BotAvatar? = nil,
        isPinned: Bool = false,
        isHidden: Bool = false,
        provider: String = "",
        model: String = "",
        soul: String = "",
        skills: [BotSettingsSkillItem] = [],
        toolsets: [BotSettingsToolsetItem] = [],
        toolsetsPinned: Bool = false,
        mcpServers: [BotSettingsMcpServerItem] = []
    ) {
        self.targetProfile = targetProfile
        self.title = title
        self.role = role
        self.avatar = avatar
        self.isPinned = isPinned
        self.isHidden = isHidden
        self.provider = provider
        self.model = model
        self.soul = soul
        self.skills = skills
        self.toolsets = toolsets
        self.toolsetsPinned = toolsetsPinned
        self.mcpServers = mcpServers

        baselineTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        baselineRole = role.trimmingCharacters(in: .whitespacesAndNewlines)
        baselineAvatar = avatar
        baselineIsPinned = isPinned
        baselineIsHidden = isHidden
        baselineProvider = provider.trimmingCharacters(in: .whitespacesAndNewlines)
        baselineModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        baselineSoul = soul.trimmingCharacters(in: .whitespacesAndNewlines)
        baselineSkills = Dictionary(uniqueKeysWithValues: skills.map { ($0.name, $0.enabled) })
        baselineToolsets = Dictionary(uniqueKeysWithValues: toolsets.map { ($0.name, $0.enabled) })
        baselineToolsetsPinned = toolsetsPinned
        baselineMcpServers = Dictionary(uniqueKeysWithValues: mcpServers.map { ($0.name, $0.enabled) })
    }

    // MARK: - Dirty Tracking

    public var isIdentityDirty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines) != baselineTitle
            || role.trimmingCharacters(in: .whitespacesAndNewlines) != baselineRole
            || avatar != baselineAvatar
            || isPinned != baselineIsPinned
            || isHidden != baselineIsHidden
    }

    /// True when metadata stored outside `profiles.configure` (title, avatar, pinned, hidden) has changed.
    public var isIdentityMetaDirty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines) != baselineTitle
            || avatar != baselineAvatar
            || isPinned != baselineIsPinned
            || isHidden != baselineIsHidden
    }

    /// True when desktop-namespace metadata (title, pinned, hidden) has changed.
    public var isDesktopMetaDirty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines) != baselineTitle
            || isPinned != baselineIsPinned
            || isHidden != baselineIsHidden
    }

    /// True when app-namespace look metadata (avatar) has changed.
    public var isAppLookDirty: Bool {
        avatar != baselineAvatar
    }

    public var isRoleDirty: Bool {
        role.trimmingCharacters(in: .whitespacesAndNewlines) != baselineRole
    }

    public var isModelDirty: Bool {
        provider.trimmingCharacters(in: .whitespacesAndNewlines) != baselineProvider
            || model.trimmingCharacters(in: .whitespacesAndNewlines) != baselineModel
    }

    public var isSoulDirty: Bool {
        soul.trimmingCharacters(in: .whitespacesAndNewlines) != baselineSoul
    }

    public var isSkillsDirty: Bool {
        for skill in skills {
            if baselineSkills[skill.name] != skill.enabled { return true }
        }
        return false
    }

    public var isToolsetsDirty: Bool {
        if toolsetsPinned != baselineToolsetsPinned { return true }
        if toolsetsPinned {
            for toolset in toolsets {
                if baselineToolsets[toolset.name] != toolset.enabled { return true }
            }
        }
        return false
    }

    public var isMcpDirty: Bool {
        for server in mcpServers {
            if baselineMcpServers[server.name] != server.enabled { return true }
        }
        return false
    }

    public var dirtySections: Set<BotSettingsSection> {
        var sections: Set<BotSettingsSection> = []
        if isIdentityDirty { sections.insert(.identity) }
        if isModelDirty { sections.insert(.model) }
        if isSoulDirty { sections.insert(.soul) }
        if isSkillsDirty { sections.insert(.skills) }
        if isToolsetsDirty { sections.insert(.toolsets) }
        if isMcpDirty { sections.insert(.mcp) }
        return sections
    }

    public var isDirty: Bool {
        !dirtySections.isEmpty
    }

    /// True when there are dirty sections to send over `profiles.configure`.
    public var hasConfigurePayload: Bool {
        isRoleDirty || isModelDirty || isSoulDirty || isSkillsDirty || isToolsetsDirty || isMcpDirty
    }

    // MARK: - Validation

    public var problems: [BotSettingsProblem] {
        var problems: [BotSettingsProblem] = []
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle.count > Self.maxTitleLength {
            problems.append(.titleTooLong(Self.maxTitleLength))
        }

        let trimmedRole = role.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedRole.count > Self.maxRoleLength {
            problems.append(.roleTooLong(Self.maxRoleLength))
        }

        let trimmedSoul = soul.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSoul.count > Self.maxSoulLength {
            problems.append(.soulTooLong(Self.maxSoulLength))
        }

        let trimmedProvider = provider.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedProvider.isEmpty != trimmedModel.isEmpty {
            problems.append(.modelIncomplete)
        }

        return problems
    }

    public var isValid: Bool {
        problems.isEmpty
    }

    // MARK: - Skills and Toolsets Helpers

    public var enabledSkillsCount: Int {
        skills.filter(\.enabled).count
    }

    public var totalSkillsCount: Int {
        skills.count
    }

    public func filteredSkills(matching query: String) -> [BotSettingsSkillItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return skills }
        return skills.filter { $0.name.lowercased().contains(trimmed) }
    }

    public mutating func toggleSkill(named name: String) {
        if let idx = skills.firstIndex(where: { $0.name == name }) {
            skills[idx].enabled.toggle()
        }
    }

    public mutating func customizeToolsets() {
        toolsetsPinned = true
    }

    public mutating func resetToolsets() {
        toolsetsPinned = baselineToolsetsPinned
        // Revert toolset states to baseline
        for toolsetIndex in toolsets.indices {
            let name = toolsets[toolsetIndex].name
            if let base = baselineToolsets[name] {
                toolsets[toolsetIndex].enabled = base
            }
        }
    }

    public mutating func toggleToolset(named name: String) {
        if let idx = toolsets.firstIndex(where: { $0.name == name }) {
            toolsets[idx].enabled.toggle()
            toolsetsPinned = true
        }
    }

    public mutating func toggleMcpServer(named name: String) {
        if let idx = mcpServers.firstIndex(where: { $0.name == name }) {
            mcpServers[idx].enabled.toggle()
        }
    }

    // MARK: - Configure Params Generation

    /// Builds `ProfilesConfigureParams` containing only dirty sections.
    /// Passes `targetProfile` as both `profile` and `name`.
    public func buildConfigureParams(confirmExpensiveModel: Bool = false) -> ProfilesConfigureParams? {
        guard hasConfigurePayload else { return nil }

        var params = ProfilesConfigureParams(profile: targetProfile, name: targetProfile)

        if isRoleDirty {
            params.description = role.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if isModelDirty {
            params.provider = provider.trimmingCharacters(in: .whitespacesAndNewlines)
            params.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
            if confirmExpensiveModel {
                params.confirmExpensiveModel = true
            }
        }

        if isSoulDirty {
            params.soul = soul.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if isSkillsDirty {
            // Inverse skills complement: send the full list of all disabled skills
            params.disabledSkills = skills.filter { !$0.enabled }.map(\.name)
        }

        if isToolsetsDirty {
            params.enabledToolsets = toolsets.filter { $0.enabled }.map(\.name)
        }

        if isMcpDirty {
            params.enabledMCPServers = mcpServers.filter { $0.enabled }.map(\.name)
        }

        return params
    }

    // MARK: - Apply Successful Outcome

    /// Updates the baseline for metadata saved outside `profiles.configure` (title, avatar, pinned, hidden).
    public mutating func applySuccessfulIdentityMeta() {
        baselineTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        baselineAvatar = avatar
        baselineIsPinned = isPinned
        baselineIsHidden = isHidden
    }

    /// Updates the baseline for sections that were successfully written, keeping failed values intact.
    public mutating func applySuccessfulSections(_ sections: Set<BotSettingsSection>) {
        if sections.contains(.identity) {
            baselineTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            baselineRole = role.trimmingCharacters(in: .whitespacesAndNewlines)
            baselineAvatar = avatar
            baselineIsPinned = isPinned
            baselineIsHidden = isHidden
        }
        if sections.contains(.model) {
            baselineProvider = provider.trimmingCharacters(in: .whitespacesAndNewlines)
            baselineModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if sections.contains(.soul) {
            baselineSoul = soul.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if sections.contains(.skills) {
            baselineSkills = Dictionary(uniqueKeysWithValues: skills.map { ($0.name, $0.enabled) })
        }
        if sections.contains(.toolsets) {
            baselineToolsets = Dictionary(uniqueKeysWithValues: toolsets.map { ($0.name, $0.enabled) })
            baselineToolsetsPinned = toolsetsPinned
        }
        if sections.contains(.mcp) {
            baselineMcpServers = Dictionary(uniqueKeysWithValues: mcpServers.map { ($0.name, $0.enabled) })
        }
    }
}

/// The result of evaluating a `profiles.configure` outcome across the requested dirty sections.
public struct BotSettingsSaveOutcome: Sendable, Equatable {
    public var isCompleteSuccess: Bool
    public var appliedSections: Set<BotSettingsSection>
    public var failedSections: Set<BotSettingsSection>
    public var confirmRequired: Bool
    public var confirmMessage: String?
    public var statusMessage: String

    public init(
        isCompleteSuccess: Bool,
        appliedSections: Set<BotSettingsSection>,
        failedSections: Set<BotSettingsSection>,
        confirmRequired: Bool = false,
        confirmMessage: String? = nil,
        statusMessage: String
    ) {
        self.isCompleteSuccess = isCompleteSuccess
        self.appliedSections = appliedSections
        self.failedSections = failedSections
        self.confirmRequired = confirmRequired
        self.confirmMessage = confirmMessage
        self.statusMessage = statusMessage
    }

    /// Evaluates the outcome of `profiles.configure` against the sections that were sent.
    public static func evaluate(
        result: ProfilesConfigureResult,
        requestedSections: Set<BotSettingsSection>,
        hasRoleDirty: Bool = false
    ) -> BotSettingsSaveOutcome {
        var applied: Set<BotSettingsSection> = []
        var failed: Set<BotSettingsSection> = []

        if requestedSections.contains(.identity) {
            let roleOk = !hasRoleDirty || result.applied.description == true
            let metaOk = result.applied.uiMeta != false
            if roleOk && metaOk {
                applied.insert(.identity)
            } else {
                failed.insert(.identity)
            }
        }

        if requestedSections.contains(.model) {
            if result.confirmRequired == true {
                // Needs confirmation; not marked as failed yet
            } else if result.applied.model == true {
                applied.insert(.model)
            } else {
                failed.insert(.model)
            }
        }

        if requestedSections.contains(.soul) {
            if result.applied.soul == true {
                applied.insert(.soul)
            } else {
                failed.insert(.soul)
            }
        }

        if requestedSections.contains(.skills) {
            if result.applied.skills == true {
                applied.insert(.skills)
            } else {
                failed.insert(.skills)
            }
        }

        if requestedSections.contains(.toolsets) {
            if result.applied.toolsets == true {
                applied.insert(.toolsets)
            } else {
                failed.insert(.toolsets)
            }
        }

        if requestedSections.contains(.mcp) {
            if result.applied.mcpServers == true {
                applied.insert(.mcp)
            } else {
                failed.insert(.mcp)
            }
        }

        let confirmReq = result.confirmRequired == true
        let complete = failed.isEmpty && !confirmReq

        let message: String
        if complete {
            message = "All changes saved."
        } else if confirmReq {
            message = result.confirmMessage ?? "Changing to this model requires confirmation."
        } else if !applied.isEmpty && !failed.isEmpty {
            let appliedNames = applied.map(\.displayName).sorted().joined(separator: ", ")
            let failedNames = failed.map(\.displayName).sorted().joined(separator: ", ")
            message = "\(appliedNames) saved, but \(failedNames) could not be updated."
        } else {
            let failedNames = failed.map(\.displayName).sorted().joined(separator: ", ")
            message = "\(failedNames) could not be saved."
        }

        return BotSettingsSaveOutcome(
            isCompleteSuccess: complete,
            appliedSections: applied,
            failedSections: failed,
            confirmRequired: confirmReq,
            confirmMessage: result.confirmMessage,
            statusMessage: message
        )
    }
}

/// User-facing error messages for bot settings operations.
public enum BotSettingsError: Sendable {
    public static func message(for error: Error) -> String {
        if let rpc = error as? RPCError {
            switch rpc.code {
            case 4062:
                return "A bot with that name already exists."
            case 4115:
                return "The server driver is unavailable. Try again later."
            default:
                return rpc.message
            }
        }
        if let bot = error as? BotError {
            switch bot {
            case .metaTooLarge:
                return "Those settings are too large to save."
            case .metaConflict:
                return "Someone else changed this bot at the same time. Try again."
            case .metaNotSaved, .roleNotSaved:
                return "The server did not save the change."
            case .profileNotFound:
                return "That bot is no longer on the server."
            case .chatInconsistent:
                return "Its chat could not be found, so nothing was opened."
            case .invalidDraft:
                return "Check the settings values."
            }
        }
        let desc = error.localizedDescription
        if desc.lowercased().contains("offline") || desc.lowercased().contains("unreachable")
            || desc.lowercased().contains("not connected")
        {
            return "The server is offline or unreachable. Check your connection."
        }
        return desc
    }
}

/// Coordinates saving dirty bot settings and confirming expensive model changes across metadata namespaces
/// and `profiles.configure`.
public struct BotSettingsCoordinator: Sendable {
    public let client: BotClient

    public init(client: BotClient) {
        self.client = client
    }

    /// Saves dirty identity metadata and/or `profiles.configure` sections.
    /// Returns the evaluated save outcome, or nil if only identity metadata was saved.
    @discardableResult
    public func save(
        draft: inout BotSettingsDraft
    ) async throws -> BotSettingsSaveOutcome? {
        // 1. Identity metadata writes
        if draft.isIdentityMetaDirty {
            if draft.isDesktopMetaDirty {
                let targetTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let targetPinned = draft.isPinned
                let targetHidden = draft.isHidden
                try await client.updateNamespace(
                    profile: draft.targetProfile, namespace: BotMetaNamespace.desktop
                ) { meta in
                    meta.title = targetTitle
                    meta.pinned = targetPinned
                    meta.hidden = targetHidden
                }
            }
            if draft.isAppLookDirty {
                let targetAvatar = draft.avatar
                try await client.updateNamespace(
                    profile: draft.targetProfile, namespace: BotMetaNamespace.app
                ) { object in
                    object = BotAppLook(avatar: targetAvatar).applied(to: object)
                }
            }
            draft.applySuccessfulIdentityMeta()
        }

        // 2. Configure dirty sections
        guard let params = draft.buildConfigureParams() else {
            return nil
        }

        let result = try await client.configureProfile(params)
        let outcome = BotSettingsSaveOutcome.evaluate(
            result: result,
            requestedSections: draft.dirtySections,
            hasRoleDirty: draft.isRoleDirty
        )

        draft.applySuccessfulSections(outcome.appliedSections)
        return outcome
    }

    /// Confirms an expensive model change carrying `confirm_expensive_model: true`.
    @discardableResult
    public func confirmExpensiveModelChange(
        draft: inout BotSettingsDraft
    ) async throws -> BotSettingsSaveOutcome {
        guard let params = draft.buildConfigureParams(confirmExpensiveModel: true) else {
            return BotSettingsSaveOutcome(
                isCompleteSuccess: false,
                appliedSections: [],
                failedSections: [],
                confirmRequired: false,
                confirmMessage: nil,
                statusMessage: "No changes to confirm."
            )
        }

        let result = try await client.configureProfile(params)
        let outcome = BotSettingsSaveOutcome.evaluate(
            result: result,
            requestedSections: draft.dirtySections,
            hasRoleDirty: draft.isRoleDirty
        )

        draft.applySuccessfulSections(outcome.appliedSections)
        return outcome
    }
}
