#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// The approved MCP catalog. A tap on an entry opens its install sheet (WP-53b).
    struct MCPCatalogView: View {
        private let model: MCPCatalogModel
        @State private var selected: MCPCatalogEntry?

        init(model: MCPCatalogModel) {
            self.model = model
        }

        var body: some View {
            List {
                Section {
                    ForEach(model.entries) { entry in
                        Button {
                            selected = entry
                        } label: {
                            MCPCatalogRow(entry: entry)
                        }
                        .tint(HermesColor.primaryText)
                        .accessibilityIdentifier("mcp.catalog.\(entry.name)")
                    }
                } footer: {
                    Text(
                        "Installing adds the server to the config. "
                            + "A server that needs a build runs it in the background."
                    )
                }
                if !model.diagnostics.isEmpty {
                    Section {
                        ForEach(model.diagnostics.indices, id: \.self) { index in
                            Text(model.diagnostics[index])
                                .font(HermesFont.footnote)
                                .foregroundStyle(HermesColor.secondaryText)
                        }
                    } header: {
                        Text("Could not load")
                    }
                }
                if let notice = model.notice {
                    Section {
                        Label(notice, systemImage: "arrow.down.circle")
                            .foregroundStyle(HermesColor.secondaryText)
                    }
                }
                if let errorText = model.errorText {
                    Section {
                        Label(errorText, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(HermesColor.destructive)
                    }
                }
            }
            .navigationTitle("Catalog")
            .overlay {
                if model.entries.isEmpty && model.errorText == nil && !model.isLoading {
                    ContentUnavailableView(
                        "Catalog is empty", systemImage: "tray",
                        description: Text("The server lists no approved servers."))
                } else if model.entries.isEmpty && model.isLoading {
                    ProgressView()
                }
            }
            .refreshable { await model.refresh() }
            .task { await model.refresh() }
            .sheet(item: $selected) { entry in
                MCPInstallSheet(model: model, entry: entry)
            }
        }
    }

    /// One catalog entry: its name, what it does, and whether it is installed.
    private struct MCPCatalogRow: View {
        let entry: MCPCatalogEntry

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.name).font(HermesFont.body.weight(.semibold))
                if let description = entry.description, !description.isEmpty {
                    Text(description)
                        .font(HermesFont.footnote)
                        .foregroundStyle(HermesColor.secondaryText)
                }
                Text(state)
                    .font(HermesFont.caption)
                    .foregroundStyle(HermesColor.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }

        private var state: String {
            guard entry.installed == true else { return "Not installed" }
            return entry.enabled == true ? "Installed and on" : "Installed and off"
        }
    }

    /// The install sheet: what the entry runs or connects to, then the variables it needs (WP-53b).
    ///
    /// Variables go into secure fields and are sent once. Blank optional variables are left out.
    private struct MCPInstallSheet: View {
        let model: MCPCatalogModel
        let entry: MCPCatalogEntry
        @Environment(\.dismiss) private var dismiss
        @State private var values: [String: String] = [:]
        @State private var errorText: String?

        init(model: MCPCatalogModel, entry: MCPCatalogEntry) {
            self.model = model
            self.entry = entry
        }

        var body: some View {
            NavigationStack {
                Form {
                    Section {
                        transportRows
                    } header: {
                        Text("What it runs")
                    } footer: {
                        if entry.needsInstall == true, let source = entry.installUrl {
                            Text(
                                "Clones \(source) and builds it on the Hermes server first. "
                                    + "That runs in the background."
                            )
                        }
                    }
                    if !variables.isEmpty {
                        variableSection
                    }
                    if let note = entry.postInstall, !note.isEmpty {
                        Section {
                            Text(note)
                                .foregroundStyle(HermesColor.secondaryText)
                        } header: {
                            Text("After the install")
                        }
                    }
                    if let errorText {
                        Section {
                            Label(errorText, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(HermesColor.destructive)
                        }
                    }
                }
                .navigationTitle(entry.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
            }
        }

        @ViewBuilder private var transportRows: some View {
            if entry.transport == "http" {
                LabeledContent {
                    Text(entry.url ?? "None")
                } label: {
                    Text("Address")
                }
            } else {
                LabeledContent {
                    Text(entry.command ?? "None")
                } label: {
                    Text("Program")
                }
                if let args = entry.args, !args.isEmpty {
                    LabeledContent {
                        Text(args.joined(separator: " "))
                    } label: {
                        Text("Arguments")
                    }
                }
            }
            if let signIn = signInLabel {
                LabeledContent {
                    Text(signIn)
                } label: {
                    Text("Sign-in")
                }
            }
        }

        private var variableSection: some View {
            Section {
                ForEach(variables, id: \.name) { variable in
                    SecureField(variable.prompt ?? variable.name, text: binding(for: variable.name))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("mcp.install.\(variable.name)")
                }
            } header: {
                Text("Variables")
            } footer: {
                Text("Values are hidden and sent once. The server keeps them and never shows them again.")
            }
        }

        private var variables: [MCPCatalogEnvVar] {
            entry.requiredEnv ?? []
        }

        private var signInLabel: String? {
            switch entry.authType ?? "none" {
            case "oauth": "OAuth"
            case "header": "Bearer token"
            case "none", "": nil
            default: entry.authType
            }
        }

        private var missingRequired: Bool {
            variables.contains { variable in
                variable.required == true && trimmed(values[variable.name]).isEmpty
            }
        }

        @ToolbarContentBuilder
        private var toolbar: some ToolbarContent {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Install") { Task { await install() } }
                    .disabled(missingRequired || model.isInstalling)
                    .accessibilityIdentifier("mcp.install.confirm")
            }
        }

        private func binding(for name: String) -> Binding<String> {
            Binding(get: { values[name] ?? "" }, set: { values[name] = $0 })
        }

        private func trimmed(_ text: String?) -> String {
            (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        /// Sends the filled-in variables. The sheet closes on success. A refusal shows the server's sentence.
        private func install() async {
            errorText = nil
            var filled: [String: String] = [:]
            for variable in variables {
                let value = trimmed(values[variable.name])
                if !value.isEmpty {
                    filled[variable.name] = value
                }
            }
            do {
                try await model.install(entry, env: filled)
                values = [:]
                dismiss()
            } catch {
                errorText = ToolsetAdminClient.message(for: error)
            }
        }
    }

    /// Shows the install sheet of the first sample entry, for previews.
    private struct MCPInstallSheetPreview: View {
        var body: some View {
            if let entry = ToolsetAdminSamples.catalog?.entries.first {
                MCPInstallSheet(model: .preview(), entry: entry)
            }
        }
    }

    #Preview("Catalog, outer", traits: .fixedLayout(width: 466, height: 678)) {
        NavigationStack { MCPCatalogView(model: .preview()) }
    }

    #Preview("Catalog, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        NavigationStack { MCPCatalogView(model: .preview()) }
    }

    #Preview("Catalog, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        NavigationStack { MCPCatalogView(model: .preview()) }
    }

    #Preview("Catalog, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        NavigationStack { MCPCatalogView(model: .preview()) }
    }

    #Preview("Install sheet, outer", traits: .fixedLayout(width: 466, height: 678)) {
        MCPInstallSheetPreview()
    }
#endif
