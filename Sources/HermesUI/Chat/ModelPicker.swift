#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// The model pill as a popup menu (plan Q22): starred models, one submenu per provider, and the reasoning level.
    /// A pick switches this chat only. The device remembers it, and the server's profile default stays as it is.
    struct ModelPicker: View {
        @Environment(\.hermesPalette) private var palette
        let chat: LiveChatModel

        /// A switch the server holds until the user agrees.
        private struct Held {
            let choice: ModelChoice
            let message: String
        }

        @State private var held: Held?
        @State private var problem: Notice?

        /// A message the user dismisses: a failed switch, or a note about one that worked.
        private struct Notice {
            let title: String
            let message: String
        }

        private static let switchFailed = "Couldn't switch model"
        private static let reasoningFailed = "Couldn't change reasoning"

        /// Explicit, because the private state above would make the memberwise initializer private.
        init(chat: LiveChatModel) {
            self.chat = chat
        }

        var body: some View {
            Menu {
                let favorites = chat.listedFavorites
                if !favorites.isEmpty {
                    Section("Favorites") {
                        ForEach(favorites, id: \.self) { choice in
                            Button {
                                pick(choice)
                            } label: {
                                Label(choice.model, systemImage: isCurrent(choice) ? "checkmark" : "star.fill")
                            }
                        }
                    }
                }
                ForEach(chat.modelOptions?.providers ?? [], id: \.slug) { provider in
                    let connected = provider.authenticated != false
                    let unavailable = Set(provider.unavailableModels ?? [])
                    Menu(connected ? provider.name : "\(provider.name) (not connected)") {
                        ForEach(provider.models ?? [], id: \.self) { name in
                            modelMenu(ModelChoice(provider: provider.slug, model: name))
                                .disabled(unavailable.contains(name))
                        }
                    }
                    .disabled(!connected)
                }
                let levels = chat.reasoningLevels
                if !levels.isEmpty {
                    Section("Reasoning") {
                        Picker("Reasoning", selection: effort) {
                            ForEach(levels, id: \.self) { level in
                                Text(level.capitalized).tag(String?.some(level))
                            }
                        }
                    }
                }
            } label: {
                Label(chat.state.info?.model ?? "Model", systemImage: "cpu")
                    .font(HermesFont.caption)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 28)
                    .background(palette.fill, in: Capsule())
            }
            .accessibilityIdentifier("composer.model")
            .alert(
                "Switch model?",
                isPresented: Binding(get: { held != nil }, set: { if !$0 { held = nil } }),
                presenting: held
            ) { pending in
                Button("Switch") { Task { await select(pending.choice, confirmed: true) } }
                Button("Cancel", role: .cancel) {}
            } message: { pending in
                Text(pending.message)
            }
            .alert(
                problem?.title ?? "Model",
                isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(problem?.message ?? "")
            }
        }

        /// One model: a submenu that switches to it or stars it.
        private func modelMenu(_ choice: ModelChoice) -> some View {
            Menu(choice.model) {
                Button {
                    pick(choice)
                } label: {
                    Label("Use This Model", systemImage: isCurrent(choice) ? "checkmark" : "arrow.right.circle")
                }
                Button {
                    chat.toggleFavorite(choice)
                } label: {
                    Label(
                        chat.preferences.isFavorite(choice) ? "Remove from Favorites" : "Add to Favorites",
                        systemImage: chat.preferences.isFavorite(choice) ? "star.slash" : "star")
                }
            }
        }

        /// The level the server reports. Nil while it reports none, which leaves every row unchecked.
        private var effort: Binding<String?> {
            Binding(
                get: { chat.state.info?.reasoningEffort.flatMap { $0.isEmpty ? nil : $0 } },
                set: { level in
                    if let level { Task { await setEffort(level) } }
                }
            )
        }

        private func isCurrent(_ choice: ModelChoice) -> Bool {
            chat.modelOptions?.model == choice.model && chat.modelOptions?.provider == choice.provider
        }

        private func pick(_ choice: ModelChoice) {
            Task { await select(choice, confirmed: false) }
        }

        /// Switches the chat. A model the server holds asks first. A warning from the server is shown.
        private func select(_ choice: ModelChoice, confirmed: Bool) async {
            do {
                switch try await chat.chooseModel(choice, confirmed: confirmed) {
                case .applied(let warning):
                    if let warning, !warning.isEmpty { problem = Notice(title: "Model", message: warning) }
                case .appliedNextTurn(let warning):
                    let note = "Applies on the next turn."
                    let message = warning.flatMap { $0.isEmpty ? nil : "\($0)\n\n\(note)" } ?? note
                    problem = Notice(title: "Model", message: message)
                case .needsConfirmation(let message):
                    held = Held(choice: choice, message: message)
                }
            } catch {
                problem = Notice(title: Self.switchFailed, message: Self.describe(error))
            }
        }

        private func setEffort(_ level: String) async {
            do {
                try await chat.chooseEffort(level)
            } catch {
                problem = Notice(title: Self.reasoningFailed, message: Self.describe(error, forReasoning: true))
            }
        }

        /// What went wrong, in words. A model pick and a reasoning change each say what stays as it was.
        private static func describe(_ error: any Error, forReasoning: Bool = false) -> String {
            if let rpc = error as? RPCError { return rpc.message }
            if let gateway = error as? GatewayClientError {
                if gateway == .notConnected {
                    return forReasoning
                        ? "This chat isn't connected yet. Send a message or wait for it to reconnect, "
                            + "then pick the reasoning level again."
                        : "This chat isn't connected yet. Send a message or wait for it to reconnect, "
                            + "then pick the model again."
                }
                return forReasoning
                    ? "The server is not reachable. The reasoning level stays as it was."
                    : "The server is not reachable. The chat stays on its current model."
            }
            return "\(error)"
        }
    }
#endif
