import Foundation

/// Values of `scope` for `POST /api/model/set`: which slot the write sets. The field is a plain string.
public enum ModelDefaultsScopes {
    /// The main model.
    public static let main = "main"
    /// An auxiliary task slot. The task names it.
    public static let auxiliary = "auxiliary"
}

/// Body of `POST /api/model/set` (`ModelAssignment`). Applies to new chats only. Not recorded on the testbed, so the
/// caller reads only the status and then reads the model again. Nil optionals are left out.
public struct ModelDefaultsAssignment: Sendable, Equatable, Codable {
    /// `main` or `auxiliary`, see ``ModelDefaultsScopes``.
    public var scope: String
    /// Provider slug, or `auto` for the server's own choice.
    public var provider: String
    /// Model id.
    public var model: String
    /// Auxiliary task name. Empty for the main slot.
    public var task: String
    /// Reasoning effort. Nil is left out of the request, so the server default applies.
    public var reasoningEffort: String?
    /// Endpoint URL, when the provider needs one.
    public var baseUrl: String?
    /// Confirms a model the server marks as expensive.
    public var confirmExpensiveModel: Bool

    /// Creates an assignment.
    public init(
        scope: String, provider: String, model: String, task: String = "", reasoningEffort: String? = nil,
        baseUrl: String? = nil, confirmExpensiveModel: Bool = false
    ) {
        self.scope = scope
        self.provider = provider
        self.model = model
        self.task = task
        self.reasoningEffort = reasoningEffort
        self.baseUrl = baseUrl
        self.confirmExpensiveModel = confirmExpensiveModel
    }
}

/// A provider and model pair. In `GET /api/model/auxiliary` it is the `main` block
/// (Fixtures/rest/GET_api_model_auxiliary.json).
public struct ModelDefaultsSlot: Sendable, Equatable, Codable {
    /// Provider slug.
    public var provider: String?
    /// Model id.
    public var model: String?

    /// Creates a value.
    public init(provider: String? = nil, model: String? = nil) {
        self.provider = provider
        self.model = model
    }
}

/// One auxiliary task row from `GET /api/model/auxiliary` (`tasks[]`). Fields are the ones the recording shows in
/// Fixtures/rest/GET_api_model_auxiliary.json. Built-in tasks come first, in the order the server sends them.
public struct ModelDefaultsAuxiliaryTask: Sendable, Equatable, Codable, Identifiable {
    /// Task name, such as `vision` or `compression`.
    public var task: String
    /// Provider stored for this task, `auto` when the server picks.
    public var provider: String?
    /// Model stored for this task, empty when none is set.
    public var model: String?
    /// Endpoint URL stored for this task, empty when none is set.
    public var baseUrl: String?
    /// Reasoning effort stored for this task. Nil when none is set.
    public var reasoningEffort: String?

    /// Identity for lists.
    public var id: String { task }

    /// Creates a value.
    public init(
        task: String, provider: String? = nil, model: String? = nil, baseUrl: String? = nil,
        reasoningEffort: String? = nil
    ) {
        self.task = task
        self.provider = provider
        self.model = model
        self.baseUrl = baseUrl
        self.reasoningEffort = reasoningEffort
    }
}

/// `GET /api/model/auxiliary`: the auxiliary task rows and the main slot. Shape from
/// Fixtures/rest/GET_api_model_auxiliary.json.
public struct ModelDefaultsAuxiliary: Sendable, Equatable, Codable {
    /// Auxiliary tasks, in the order the server sends them.
    public var tasks: [ModelDefaultsAuxiliaryTask]
    /// The main model, for reference.
    public var main: ModelDefaultsSlot?

    /// Creates a value.
    public init(tasks: [ModelDefaultsAuxiliaryTask], main: ModelDefaultsSlot? = nil) {
        self.tasks = tasks
        self.main = main
    }
}

/// `GET /api/model/recommended-default`. `model` may be empty; the caller then leaves the field to the user.
/// Fields from Fixtures/rest/GET_api_model_recommended-default.json; its `free_tier` is recorded only as null, so it is
/// not typed.
public struct ModelDefaultsRecommendation: Sendable, Equatable, Codable {
    /// Provider the recommendation is for.
    public var provider: String?
    /// Recommended model id, possibly empty.
    public var model: String?

    /// Creates a value.
    public init(provider: String? = nil, model: String? = nil) {
        self.provider = provider
        self.model = model
    }
}
