#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// Add or update a custom endpoint: name, base URL, model, optional key and API mode. Validate before you save.
    struct ProviderCustomEndpointSheet: View {
        @Bindable var form: ProviderCustomEndpointModel
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationStack {
                Form {
                    Section {
                        TextField("Name", text: $form.name)
                            .accessibilityIdentifier("endpoint.name")
                        TextField("Base URL, such as http://192.168.1.20:8000/v1", text: $form.baseUrl)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("endpoint.url")
                        TextField("Model id", text: $form.modelId)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("endpoint.model")
                        SecureField("API key (optional)", text: $form.apiKey)
                            .textContentType(.password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("endpoint.key")
                    } header: {
                        Text("Endpoint")
                    } footer: {
                        Text("The key goes to your Hermes server and is not kept on this phone.")
                    }
                    Section {
                        Picker("API mode", selection: $form.apiMode) {
                            Text("Automatic").tag(Optional<String>.none)
                            ForEach(ProviderAPIModes.options, id: \.self) { mode in
                                Text(ProviderModeLabel.title(for: mode)).tag(Optional(mode))
                            }
                        }
                        TextField("Context length (optional)", text: $form.contextLengthText)
                            .keyboardType(.numberPad)
                        Toggle("Discover models", isOn: $form.discoverModels)
                        Toggle("Use as default", isOn: $form.makeDefault)
                    } footer: {
                        Text("Use as default makes this endpoint the provider for new chats.")
                    }
                    Section {
                        Button("Validate") {
                            Task { await form.validate() }
                        }
                        .disabled(!form.canSubmit || form.isWorking)
                        .accessibilityIdentifier("endpoint.validate")
                        if let validationText = form.validationText {
                            Text(validationText)
                                .font(HermesFont.codeSmall)
                                .textSelection(.enabled)
                        }
                    }
                    if let errorText = form.errorText {
                        Section {
                            Label(errorText, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(HermesColor.destructive)
                        }
                    }
                }
                .navigationTitle("Custom endpoint")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            Task { await form.save() }
                        }
                        .disabled(!form.canSubmit || form.isWorking)
                        .accessibilityIdentifier("endpoint.save")
                    }
                }
                .onChange(of: form.didSave) { _, saved in
                    if saved { dismiss() }
                }
            }
        }
    }

    #Preview("Custom endpoint, outer", traits: .fixedLayout(width: 466, height: 678)) {
        ProviderCustomEndpointSheet(form: ProviderCustomEndpointModel(connections: .preview()))
    }

    #Preview("Custom endpoint, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        ProviderCustomEndpointSheet(form: ProviderCustomEndpointModel(connections: .preview()))
    }

    #Preview("Custom endpoint, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        ProviderCustomEndpointSheet(form: ProviderCustomEndpointModel(connections: .preview()))
    }

    #Preview("Custom endpoint, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        ProviderCustomEndpointSheet(form: ProviderCustomEndpointModel(connections: .preview()))
    }
#endif
