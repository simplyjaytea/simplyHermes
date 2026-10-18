#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// Add an MCP server: a program the Hermes server starts, or an address it connects to (WP-53b).
    ///
    /// Variable values and tokens are typed into secure fields and sent once. The server keeps them and never returns
    /// them, so the form never shows them again.
    struct MCPServerFormView: View {
        private let model: MCPServersModel
        private let onDone: () -> Void
        @State private var draft = MCPServerDraft()
        @State private var errorText: String?
        @State private var isSaving = false

        init(model: MCPServersModel, onDone: @escaping () -> Void) {
            self.model = model
            self.onDone = onDone
        }

        var body: some View {
            NavigationStack {
                Form {
                    Section {
                        TextField("Name, such as github", text: $draft.name)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("mcp.form.name")
                        Picker("Type", selection: $draft.transport) {
                            Text("Program").tag(MCPTransport.command)
                            Text("Address").tag(MCPTransport.url)
                        }
                    } footer: {
                        Text(
                            "Each server needs a unique name. A program runs on the Hermes server, not on this iPhone.")
                    }
                    switch draft.transport {
                    case .command: commandSections
                    case .url: addressSections
                    }
                    if let errorText {
                        Section {
                            Label(errorText, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(HermesColor.destructive)
                        }
                    }
                }
                .navigationTitle("Add MCP server")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
            }
        }

        @ViewBuilder private var commandSections: some View {
            Section {
                TextField("Program, such as npx", text: $draft.command)
                    .font(HermesFont.code)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("mcp.form.command")
                TextField("Arguments, one per line", text: $draft.argumentsText, axis: .vertical)
                    .font(HermesFont.code)
                    .lineLimit(1...5)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Program")
            }
            Section {
                ForEach($draft.env) { $pair in
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Name, such as API_KEY", text: $pair.key)
                            .font(HermesFont.codeSmall)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                        SecureField("Value", text: $pair.value)
                            .font(HermesFont.code)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
                .onDelete { draft.env.remove(atOffsets: $0) }
                Button("Add variable", systemImage: "plus") {
                    draft.env.append(MCPEnvPair())
                }
            } header: {
                Text("Variables")
            } footer: {
                Text("Values are hidden. The server keeps them and never shows them again.")
            }
        }

        @ViewBuilder private var addressSections: some View {
            Section {
                TextField("https://example.com/mcp", text: $draft.url)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("mcp.form.url")
                Picker("Sign in", selection: $draft.auth) {
                    Text("None").tag(MCPAuthChoice.none)
                    Text("Bearer token").tag(MCPAuthChoice.bearerToken)
                    Text("OAuth").tag(MCPAuthChoice.oauth)
                }
                if draft.auth == .bearerToken {
                    SecureField("Bearer token", text: $draft.bearerToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("mcp.form.token")
                }
            } header: {
                Text("Address")
            } footer: {
                Text(authFooter)
            }
        }

        private var authFooter: String {
            switch draft.auth {
            case .none: "The app sends no token to this server."
            case .bearerToken: "The token is sent in the Authorization header. The server keeps it and never shows it."
            case .oauth: "After the server is added, sign in from its row."
            }
        }

        @ToolbarContentBuilder
        private var toolbar: some ToolbarContent {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onDone)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") { Task { await add() } }
                    .disabled(isSaving)
                    .accessibilityIdentifier("mcp.form.add")
            }
        }

        /// Checks the draft, then adds the server. The sheet closes on success. A refusal shows the server's sentence.
        private func add() async {
            errorText = nil
            do {
                let request = try draft.request()
                isSaving = true
                defer { isSaving = false }
                try await model.add(request)
                onDone()
            } catch let problem as MCPDraftProblem {
                errorText = problem.message
            } catch {
                errorText = ToolsetAdminClient.message(for: error)
            }
        }
    }

    #Preview("Add MCP server, outer", traits: .fixedLayout(width: 466, height: 678)) {
        MCPServerFormView(model: .preview()) {}
    }

    #Preview("Add MCP server, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        MCPServerFormView(model: .preview()) {}
    }

    #Preview("Add MCP server, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        MCPServerFormView(model: .preview()) {}
    }

    #Preview("Add MCP server, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        MCPServerFormView(model: .preview()) {}
    }
#endif
