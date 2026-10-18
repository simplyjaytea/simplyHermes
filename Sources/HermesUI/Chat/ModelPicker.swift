#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// The model pill as a popup menu (plan Q22): starred models, one submenu per provider, and the reasoning level.
    /// A pick switches this chat only. The device remembers it, and the server's profile default stays as it is.
    struct ModelPicker: View {
        let chat: LiveChatModel

        /// A switch the server holds until the user agrees.
        private struct Held {
            let choice: ModelChoice
            let message: String
        }

        @State private var held: Held?
        @State private var problem: String?

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
                    Menu(provider.name) {
                        ForEach(provider.models ?? [], id: \.self) { name in
                            modelMenu(ModelChoice(provider: provider.slug, model: name))
                        }
                    }
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
                    .background(HermesColor.fill, in: Capsule())
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
            .alert("Model", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(problem ?? "")
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
                    if let warning, !warning.isEmpty { problem = warning }
                case .needsConfirmation(let message):
                    held = Held(choice: choice, message: message)
                }
            } catch {
                problem = Self.describe(error)
            }
        }

        private func setEffort(_ level: String) async {
            do {
                try await chat.chooseEffort(level)
            } catch {
                problem = Self.describe(error)
            }
        }

        private static func describe(_ error: any Error) -> String {
            if let rpc = error as? RPCError { return rpc.message }
            if error is GatewayClientError { return "The server is not reachable." }
            return "\(error)"
        }
    }
#endif
