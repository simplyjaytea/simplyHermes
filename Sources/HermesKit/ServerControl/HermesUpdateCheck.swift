import Foundation

/// `GET /api/hermes/update/check`. Each field is a key of Fixtures/rest/GET_api_hermes_update_check.json, read by its
/// type. The recorder captured two shapes: the committed success answer, and an error answer with no `commits` key
/// and a null `behind`. Its exact body is in Fixtures/rest/README.md. So every field is optional. Values vary between
/// recorder runs, so the docs name types. Each field is read on its own: a field of an unexpected type is nil.
public struct HermesUpdateCheck: Sendable, Equatable, Decodable {
    /// `install_method`, a string in GET_api_hermes_update_check.json.
    public var installMethod: String?
    /// `current_version`, a string in GET_api_hermes_update_check.json.
    public var currentVersion: String?
    /// `behind`, an integer in GET_api_hermes_update_check.json. Null in the error answer.
    /// A missing count does not mean up to date (see ``isUpToDate``).
    public var behind: Int?
    /// `update_available`, a boolean in GET_api_hermes_update_check.json. False in the error answer.
    public var updateAvailable: Bool?
    /// `can_apply`, a boolean in GET_api_hermes_update_check.json.
    public var canApply: Bool?
    /// `update_command`, a string in GET_api_hermes_update_check.json.
    public var updateCommand: String?
    /// `message`. Null in the committed copy of GET_api_hermes_update_check.json. In the error answer it is the error
    /// text (Fixtures/rest/README.md has that body).
    public var message: String?
    /// `commits`, a list in GET_api_hermes_update_check.json. Absent in the error answer.
    /// The keys of its entries are not recorded, so each entry is kept as JSON.
    public var commits: [JSONValue]?

    /// True when no update exists and the check gives a count behind. A false `update_available` with no count is
    /// not up to date: the error answer has that shape.
    public var isUpToDate: Bool {
        updateAvailable == false && behind != nil
    }

    private enum CodingKeys: String, CodingKey {
        case installMethod, currentVersion, behind, updateAvailable, canApply, updateCommand, message, commits
    }

    /// Reads each field on its own.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        installMethod = try? values.decodeIfPresent(String.self, forKey: .installMethod)
        currentVersion = try? values.decodeIfPresent(String.self, forKey: .currentVersion)
        behind = try? values.decodeIfPresent(Int.self, forKey: .behind)
        updateAvailable = try? values.decodeIfPresent(Bool.self, forKey: .updateAvailable)
        canApply = try? values.decodeIfPresent(Bool.self, forKey: .canApply)
        updateCommand = try? values.decodeIfPresent(String.self, forKey: .updateCommand)
        message = try? values.decodeIfPresent(String.self, forKey: .message)
        commits = try? values.decodeIfPresent([JSONValue].self, forKey: .commits)
    }

    /// Creates a value from its fields, for previews and tests.
    public init(
        installMethod: String? = nil, currentVersion: String? = nil, behind: Int? = nil,
        updateAvailable: Bool? = nil, canApply: Bool? = nil, updateCommand: String? = nil, message: String? = nil,
        commits: [JSONValue]? = nil
    ) {
        self.installMethod = installMethod
        self.currentVersion = currentVersion
        self.behind = behind
        self.updateAvailable = updateAvailable
        self.canApply = canApply
        self.updateCommand = updateCommand
        self.message = message
        self.commits = commits
    }
}
