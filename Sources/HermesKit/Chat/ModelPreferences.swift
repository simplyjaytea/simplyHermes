import Foundation

/// A model on a provider, as the picker lists it.
public struct ModelChoice: Sendable, Hashable, Codable {
    /// Provider slug, such as `openrouter`.
    public var provider: String
    /// Model name, as the provider lists it.
    public var model: String

    /// Creates a choice.
    public init(provider: String, model: String) {
        self.provider = provider
        self.model = model
    }

    /// The value `config.set` takes for the `model` key: `<model> --provider <provider> --session`. The provider is
    /// always named, because the server reads `vendor:model` as a model on the current provider. `--session` keeps the
    /// pick to this chat, so the server's profile default stays. The server splits the text on white space, so a model
    /// name with a space in it cannot be sent.
    /// Send ``ModelOptionsResult/configValue(for:)`` when the server's model list is at hand: it knows the one provider
    /// that must not be named.
    public var configValue: String {
        "\(model) --provider \(provider) --session"
    }
}

/// What the picker remembers on this device: starred models, and the model and reasoning level picked last. The picks
/// go to one chat at a time, so the profile default on the server does not change.
public struct ModelPreferences: Sendable, Equatable, Codable {
    /// Starred models, in the order they were starred.
    public private(set) var favorites: [ModelChoice] = []
    /// The model picked last on this device. Nil until the first pick.
    public var sticky: ModelChoice?
    /// The reasoning level picked last on this device.
    public var stickyEffort: String?

    /// Creates empty preferences.
    public init() {}

    /// True when the model is starred.
    public func isFavorite(_ choice: ModelChoice) -> Bool {
        favorites.contains(choice)
    }

    /// Stars a model, or unstars it when it is already starred.
    public mutating func toggleFavorite(_ choice: ModelChoice) {
        if let index = favorites.firstIndex(of: choice) {
            favorites.remove(at: index)
        } else {
            favorites.append(choice)
        }
    }

    /// The starred models that `options` lists. A model starred on another server or profile stays out of the menu.
    public func listedFavorites(in options: ModelOptionsResult) -> [ModelChoice] {
        favorites.filter { options.lists($0) }
    }

    /// The `config.set` calls that bring a chat to the remembered pick. Empty when the chat already matches. `options`
    /// is the model list of the server the chat is on. A model it does not list is never sent. A reasoning level goes
    /// only when the list says the chat's model reasons, and "none" only when it says reasoning can be off.
    public func restoreParams(
        for info: SessionInfo, sessionID: String, options: ModelOptionsResult
    ) -> [ConfigSetParams] {
        var params: [ConfigSetParams] = []
        let provider = info.provider ?? options.provider
        var running: ModelChoice?
        if let provider, let model = info.model ?? options.model {
            running = ModelChoice(provider: provider, model: model)
        }
        if let sticky, sticky != running, options.lists(sticky) {
            params.append(ConfigSetParams(key: "model", value: options.configValue(for: sticky), sessionID: sessionID))
            running = sticky
        }
        let levels = running.map { options.reasoningLevels(for: $0) } ?? []
        if let stickyEffort, levels.contains(stickyEffort), stickyEffort != info.reasoningEffort {
            params.append(
                ConfigSetParams(key: "reasoning", value: stickyEffort, sessionID: sessionID, scope: "session"))
        }
        return params
    }
}

/// Saves ``ModelPreferences`` on this device. Every chat the device opens shares the saved copy.
public enum ModelPreferencesStore {
    private static let key = "model.preferences"

    /// The saved preferences, or the defaults when nothing is saved.
    public static func load(from defaults: UserDefaults = .standard) -> ModelPreferences {
        guard let data = defaults.data(forKey: key) else { return ModelPreferences() }
        return (try? JSONDecoder().decode(ModelPreferences.self, from: data)) ?? ModelPreferences()
    }

    /// Saves the preferences. A failed write leaves the saved copy as it was.
    public static func save(_ preferences: ModelPreferences, to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: key)
    }
}
