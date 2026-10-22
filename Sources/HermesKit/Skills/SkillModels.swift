import Foundation

/// `GET /api/skills/content?name=`: a skill's SKILL.md as the server reads it.
public struct SkillContent: Sendable, Equatable, Codable {
    /// Skill name.
    public var name: String
    /// The full SKILL.md text.
    public var content: String
    /// Where the file is on the server.
    public var path: String?
}

/// The answer of `POST /api/skills` and `PUT /api/skills/content`. A refused write answers `400` or `404` with a `detail`.
public struct SkillWriteResult: Sendable, Equatable, Codable {
    /// True when the skill was written.
    public var success: Bool?
    /// What happened, for display.
    public var message: String?
    /// Where the skill is on the server.
    public var path: String?
    /// A note when the description is too long for the system prompt.
    public var systemPromptPreview: String?
}

/// The answer of `PUT /api/skills/toggle`.
public struct SkillToggleResult: Sendable, Equatable, Codable {
    /// True when the change was saved.
    public var ok: Bool?
    /// Skill name.
    public var name: String?
    /// The state now saved.
    public var enabled: Bool?
}

/// Where an installed skill came from, as `GET /api/skills` labels it. Unknown labels read as ``other``.
public enum SkillProvenance: String, Sendable, Equatable, CaseIterable {
    /// Installed from the hub.
    case hub
    /// Shipped with Hermes.
    case bundled
    /// Mounted from `skills.external_dirs`.
    case external
    /// Written by the agent or by hand on this server.
    case agent
    /// A label this app does not know.
    case other

    /// Reads the server's label. Nil and unknown labels become ``other``.
    public init(label: String?) {
        self = label.flatMap(SkillProvenance.init(rawValue:)) ?? .other
    }

    /// True for skills the user may uninstall from the app. Only hub installs can be removed through the hub.
    public var isHubInstall: Bool { self == .hub }
}

/// One skill in a hub listing: the official catalog, a search or the featured list. Fields the server leaves out are nil.
public struct HubSkill: Sendable, Equatable, Codable, Identifiable {
    /// Skill name.
    public var name: String
    /// One-line description.
    public var description: String?
    /// Hub source, such as `official`, `github` or `skills-sh`.
    public var source: String?
    /// What install takes, such as `official/research/arxiv`.
    public var identifier: String?
    /// `builtin`, `trusted` or `community`.
    public var trustLevel: String?
    /// Git repository the skill comes from.
    public var repo: String?
    /// Search tags.
    public var tags: [String]?
    /// Category from the catalog identifier. Official catalog rows only.
    public var category: String?
    /// True when the profile has it installed. Official catalog rows only.
    public var installed: Bool?

    /// Identity for lists: the install identifier, or the name when the server omits it.
    public var id: String { identifier ?? name }
}

/// `GET /api/skills/hub/official`: the whole optional-skills catalog, with installed rows marked for the profile.
public struct OfficialSkillCatalog: Sendable, Equatable, Codable {
    /// Every catalog skill.
    public var skills: [HubSkill]
}

/// One hub source in `GET /api/skills/hub/sources`.
public struct SkillHubSource: Sendable, Equatable, Codable, Identifiable {
    /// Source id, such as `official` or `github`.
    public var id: String
    /// Name to show.
    public var label: String?
    /// GitHub only: true while the rate limit holds.
    public var rateLimited: Bool?
    /// Hermes index only: true when the index answers.
    public var available: Bool?
    /// False when the Hermes index already covers this source in searches.
    public var searchable: Bool?
}

/// A hub skill the profile has installed, as `installed` maps it by identifier.
public struct SkillHubInstall: Sendable, Equatable, Codable {
    /// Skill name.
    public var name: String?
    /// `builtin`, `trusted` or `community`.
    public var trustLevel: String?
    /// The verdict of the scan at install time.
    public var scanVerdict: String?
}

/// `GET /api/skills/hub/sources`: the configured sources, the featured skills and what is installed.
public struct SkillHubSources: Sendable, Equatable, Codable {
    /// Configured sources.
    public var sources: [SkillHubSource]
    /// True when the Hermes index answers.
    public var indexAvailable: Bool?
    /// Featured and popular skills, shown before a search.
    public var featured: [HubSkill]?
    /// Installed hub skills by identifier.
    public var installed: [String: SkillHubInstall]?
}

/// `GET /api/skills/hub/search`. An empty query answers no results.
public struct SkillHubSearch: Sendable, Equatable, Codable {
    /// Matches, one per identifier.
    public var results: [HubSkill]
    /// Matches per source id.
    public var sourceCounts: [String: Int]?
    /// Sources that did not answer in time.
    public var timedOut: [String]?
    /// Installed hub skills by identifier.
    public var installed: [String: SkillHubInstall]?
}

/// `GET /api/skills/hub/preview?identifier=`: a hub skill's SKILL.md and file list, read without installing it.
public struct SkillHubPreview: Sendable, Equatable, Codable {
    /// Skill name.
    public var name: String
    /// One-line description.
    public var description: String?
    /// Hub source.
    public var source: String?
    /// Install identifier.
    public var identifier: String?
    /// `builtin`, `trusted` or `community`.
    public var trustLevel: String?
    /// Git repository.
    public var repo: String?
    /// Search tags.
    public var tags: [String]?
    /// The SKILL.md text.
    public var skillMd: String?
    /// Relative paths of the files in the skill.
    public var files: [String]?
}

/// One finding of a hub scan.
public struct SkillHubScanFinding: Sendable, Equatable, Codable {
    /// `critical`, `high`, `medium` or `low`.
    public var severity: String?
    /// What kind of risk the rule covers.
    public var category: String?
    /// File the finding is in.
    public var file: String?
    /// Line in that file.
    public var line: Int?
    /// What the scanner saw.
    public var description: String?
}

/// `GET /api/skills/hub/scan?identifier=`: the install-time security scan of a hub skill, run without installing it.
public struct SkillHubScan: Sendable, Equatable, Codable {
    /// Skill name.
    public var name: String?
    /// Install identifier.
    public var identifier: String?
    /// Hub source.
    public var source: String?
    /// `builtin`, `trusted` or `community`.
    public var trustLevel: String?
    /// The scanner's verdict. Its values are the server's own words.
    public var verdict: String?
    /// One-line summary.
    public var summary: String?
    /// `allow`, `ask` or `block`: what installing would do.
    public var policy: String?
    /// Why the policy says so.
    public var policyReason: String?
    /// Every finding.
    public var findings: [SkillHubScanFinding]?
    /// Findings per severity: `critical`, `high`, `medium` and `low`.
    public var severityCounts: [String: Int]?
}
