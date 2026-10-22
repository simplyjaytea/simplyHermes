#if canImport(UIKit)
    import Foundation
    import HermesKit
    import SwiftUI

    /// Webhooks > New webhook. Only the name is required. The secret goes in a secure field, is held only while this
    /// screen is open, and is never shown again.
    struct WebhookCreateView: View {
        let model: MessagingServerModel
        @State private var name = ""
        @State private var detail = ""
        @State private var events = ""
        @State private var prompt = ""
        @State private var script = ""
        @State private var skills = ""
        @State private var deliver = "log"
        @State private var deliverOnly = false
        @State private var deliverChatId = ""
        @State private var secret = ""
        @State private var isSaving = false
        @Environment(\.dismiss) private var dismiss

        init(model: MessagingServerModel) {
            self.model = model
        }

        var body: some View {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("webhook.create.name")
                    TextField("What it is for", text: $detail)
                    TextField("Events, comma separated", text: $events)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Webhook")
                }
                Section {
                    TextField("Prompt for the agent", text: $prompt, axis: .vertical)
                        .lineLimit(3...8)
                    TextField("Script", text: $script, axis: .vertical)
                        .lineLimit(1...5)
                        .font(HermesFont.code)
                    TextField("Skills, comma separated", text: $skills)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("What it runs")
                }
                Section {
                    TextField("Deliver to", text: $deliver)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Toggle("Deliver only", isOn: $deliverOnly)
                    TextField("Chat id", text: $deliverChatId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Delivery")
                }
                Section {
                    SecureField("Secret", text: $secret)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("webhook.create.secret")
                } footer: {
                    Text("The secret is sent to your Hermes server. It is not saved on this phone.")
                }
            }
            .navigationTitle("New webhook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: create)
                        .disabled(!canCreate || isSaving)
                        .accessibilityIdentifier("webhook.create")
                }
            }
        }

        private var canCreate: Bool {
            !name.messagingTrimmed.isEmpty
        }

        private func create() {
            let draft = WebhookCreate(
                name: name.messagingTrimmed,
                description: Self.trimmedOrNil(detail),
                events: Self.words(events),
                prompt: Self.trimmedOrNil(prompt),
                script: Self.trimmedOrNil(script),
                skills: Self.words(skills),
                deliver: Self.trimmedOrNil(deliver) ?? "log",
                deliverOnly: deliverOnly,
                deliverChatId: Self.trimmedOrNil(deliverChatId),
                secret: Self.trimmedOrNil(secret))
            isSaving = true
            Task {
                let saved = await model.perform("Webhook created.") { try await $0.createWebhook(draft) }
                isSaving = false
                if saved { dismiss() }
            }
        }

        /// The text trimmed, or nil when it is empty.
        private static func trimmedOrNil(_ text: String) -> String? {
            let trimmed = text.messagingTrimmed
            return trimmed.isEmpty ? nil : trimmed
        }

        /// Comma-separated words, trimmed, without empty entries.
        private static func words(_ text: String) -> [String] {
            text.split(separator: ",").map { String($0).messagingTrimmed }.filter { !$0.isEmpty }
        }
    }

    #Preview("New webhook, outer", traits: .fixedLayout(width: 466, height: 678)) {
        NavigationStack { WebhookCreateView(model: .preview()) }
    }

    #Preview("New webhook, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        NavigationStack { WebhookCreateView(model: .preview()) }
    }

    #Preview("New webhook, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        NavigationStack { WebhookCreateView(model: .preview()) }
    }

    #Preview("New webhook, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        NavigationStack { WebhookCreateView(model: .preview()) }
    }
#endif
