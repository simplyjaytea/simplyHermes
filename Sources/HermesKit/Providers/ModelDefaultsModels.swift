import Foundation

/// Which slot `POST /api/model/set` writes.
public enum ModelDefaultsScope: String, Sendable, Equatable, Codable {
    /// The main model.
    case main
    /// An auxiliary task slot. The task names it.
    case auxiliary
}

/// Body of `POST /api/model/set` (`ModelAssignment`). Applies to new chats only.
public struct ModelDefaultsAssignment: Sendable, Equatable, Codable {
    /// `main` or `auxiliary`.
    public var scope: ModelDefaultsScope
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
    /// Set only when the write carries its own key. Nil is left out.
    public var apiKey: String?
    /// Confirms a model the server marks as expensive.
    public var confirmExpensiveModel: Bool

    /// Creates an assignment. Optional fields that are nil are left out of the request.
    public init(
        scope: ModelDefaultsScope, provider: String, model: String, task: String = "", reasoningEffort: String? = nil,
        baseUrl: String? = nil, apiKey: String? = nil, confirmExpensiveModel: Bool = false
    ) {
        self.scope = scope
        self.provider = provider
        self.model = model
        self.task = task
        self.reasoningEffort = reasoningEffort
        self.baseUrl = baseUrl
        self.apiKey = apiKey
        self.confirmExpensiveModel = confirmExpensiveModel
    }
}

/// A provider and model pair, as `GET /api/model/auxiliary` reports the main slot.
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

/// One auxiliary task row from `GET /api/model/auxiliary`. The row's own provider, model and base URL are its stored
/// values. `effective` (what an inheriting row resolves to) is not modelled.
public struct ModelDefaultsAuxiliaryTask: Sendable, Equatable, Codable, Identifiable {
    /// Task name. Built-in names come first in the list.
    public var task: String
    /// Provider stored for this task.
    public var provider: String?
    /// Model stored for this task.
    public var model: String?
    /// Endpoint URL stored for this task.
    public var baseUrl: String?
    /// Name a plugin declared for the task. Built-in tasks have none.
    public var label: String?
    /// Hint a plugin declared for the task.
    public var hint: String?
    /// Plugin that registered the task, when it is not built in.
    public var plugin: String?
    /// Slot this task inherits from when it is not pinned.
    public var inheritFrom: String?

    /// Identity for lists.
    public var id: String { task }

    /// Creates a value.
    public init(
        task: String, provider: String? = nil, model: String? = nil, baseUrl: String? = nil, label: String? = nil,
        hint: String? = nil, plugin: String? = nil, inheritFrom: String? = nil
    ) {
        self.task = task
        self.provider = provider
        self.model = model
        self.baseUrl = baseUrl
        self.label = label
        self.hint = hint
        self.plugin = plugin
        self.inheritFrom = inheritFrom
    }
}

/// `GET /api/model/auxiliary`: the auxiliary task rows and the main slot.
public struct ModelDefaultsAuxiliary: Sendable, Equatable, Codable {
    /// Built-in tasks first, then plugin tasks.
    public var tasks: [ModelDefaultsAuxiliaryTask]
    /// The main model, for reference.
    public var main: ModelDefaultsSlot?

    /// Creates a value.
    public init(tasks: [ModelDefaultsAuxiliaryTask], main: ModelDefaultsSlot? = nil) {
        self.tasks = tasks
        self.main = main
    }
}

/// `GET /api/model/recommended-default?provider=`. `model` may be empty; the caller then leaves the field to the user.
public struct ModelDefaultsRecommendation: Sendable, Equatable, Codable {
    /// Provider the recommendation is for.
    public var provider: String?
    /// Recommended model id, possibly empty.
    public var model: String?
    /// Set for Nous only: true for a free-tier model.
    public var freeTier: Bool?

    /// Creates a value.
    public init(provider: String? = nil, model: String? = nil, freeTier: Bool? = nil) {
        self.provider = provider
        self.model = model
        self.freeTier = freeTier
    }
}
