import Foundation

/// What the New Agent sheet collects (plan Q34: one sheet, Advanced collapsed). Checks run here, because the server
/// reports only the first failure and Hermes Desktop checks none of them (WP-42 contract, plan 2.5).
public struct NewAgentDraft: Sendable, Equatable {
    public enum Problem: Sendable, Equatable {
        case nameMissing
        case nameInvalid
        case nameReserved
        case nameTaken
        /// Provider and model are both needed for a model pin. One without the other is refused.
        case modelIncomplete
    }

    public var name: String
    /// The optional shown title. Empty means the name is shown, title-cased.
    public var title: String
    /// The role text, sent as the profile description.
    public var roleDescription: String
    public var avatar: BotAvatar?
    /// The profile to copy from. Nil creates a fresh profile.
    public var cloneFrom: String?
    public var provider: String
    public var model: String
    /// A custom SOUL. Empty means the generated one (`BotSoul`).
    public var soul: String
    /// Share the default profile's sign-ins, instead of copying them.
    public var shareAuth: Bool
    public var noSkills: Bool
    /// Skills the staged list turned off. Nil leaves the skills as the clone source has them.
    public var disabledSkills: [String]?
    public var enabledToolsets: [String]?
    public var enabledMCPServers: [String]?

    public init(
        name: String = "", title: String = "", roleDescription: String = "", avatar: BotAvatar? = nil,
        cloneFrom: String? = "default", provider: String = "", model: String = "", soul: String = "",
        shareAuth: Bool = true, noSkills: Bool = false, disabledSkills: [String]? = nil,
        enabledToolsets: [String]? = nil, enabledMCPServers: [String]? = nil
    ) {
        self.name = name
        self.title = title
        self.roleDescription = roleDescription
        self.avatar = avatar
        self.cloneFrom = cloneFrom
        self.provider = provider
        self.model = model
        self.soul = soul
        self.shareAuth = shareAuth
        self.noSkills = noSkills
        self.disabledSkills = disabledSkills
        self.enabledToolsets = enabledToolsets
        self.enabledMCPServers = enabledMCPServers
    }

    /// The profile name the draft creates.
    public var profileName: String {
        BotNaming.slug(name.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The title typed, else the typed name when it has text outside printable ASCII, else empty.
    public var shownTitle: String {
        let typedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typedTitle.isEmpty { return typedTitle }
        let typedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let needsTitle = typedName.unicodeScalars.contains { $0.value < 0x20 || $0.value > 0x7E }
        return needsTitle ? typedName : ""
    }

    /// Everything that blocks Create. `existingProfiles` are the profile names already on the target gateway.
    public func problems(existingProfiles: Set<String>) -> [Problem] {
        let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return [.nameMissing] }
        var found: [Problem] = []
        let slug = profileName
        if BotNaming.reservedNames.contains(slug) {
            found.append(.nameReserved)
        } else if !BotNaming.isValidProfileName(slug) {
            found.append(.nameInvalid)
        } else if existingProfiles.contains(slug) {
            found.append(.nameTaken)
        }
        let hasProvider = !provider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasModel = !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasProvider != hasModel { found.append(.modelIncomplete) }
        return found
    }

    /// The SOUL that is written: the custom text when there is one, else the generated text.
    public var resolvedSoul: String {
        let custom = soul.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty { return custom }
        return BotSoul.generated(
            name: profileName,
            displayName: BotNaming.displayName(profile: profileName, title: shownTitle, displayName: nil),
            title: shownTitle, mission: roleDescription.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// `profiles.create`. The server refuses `no_skills` together with a clone source, so a fresh profile sends no source.
    public func createParams() -> ProfilesCreateParams {
        let description = [shownTitle, roleDescription.trimmingCharacters(in: .whitespacesAndNewlines)]
            .filter { !$0.isEmpty }
            .joined(separator: " — ")
        let hasPin =
            !provider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return ProfilesCreateParams(
            name: profileName,
            description: description.isEmpty ? nil : description,
            cloneFrom: noSkills ? nil : cloneFrom,
            noSkills: noSkills,
            soul: resolvedSoul,
            model: hasPin ? model.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            provider: hasPin ? provider.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            shareAuth: shareAuth)
    }

    /// `profiles.configure` for the staged skills, toolsets and MCP servers. Nil when the user changed none of them.
    public func stagedConfigureParams() -> ProfilesConfigureParams? {
        guard disabledSkills != nil || enabledToolsets != nil || enabledMCPServers != nil else { return nil }
        return ProfilesConfigureParams(
            profile: profileName, name: profileName, disabledSkills: disabledSkills, enabledToolsets: enabledToolsets,
            enabledMCPServers: enabledMCPServers)
    }
}

/// The SOUL a bot gets when the draft has none (Desktop `soul.ts`). The server appends its teammate protocol itself
/// when `bot_mode_protocol` is on, so this text does not carry it.
public enum BotSoul {
    public static func generated(name: String, displayName: String, title: String, mission: String) -> String {
        var lines = ["# \(displayName)", ""]
        if !title.isEmpty { lines.append("**Role:** \(title)") }
        if !mission.isEmpty { lines.append("**Mission:** \(mission)") }
        if lines.count > 2 { lines.append("") }
        lines.append("You are \(displayName), a persistent named agent (profile `\(name)`) on this machine.")
        lines.append("You keep your own memory, skills, and conversation history across sessions.")
        return lines.joined(separator: "\n")
    }
}
