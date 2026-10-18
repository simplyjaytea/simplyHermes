#if canImport(UIKit)
    import Foundation
    import HermesKit
    import SwiftUI

    /// Settings > Messaging > Channels. Lists each platform with its state and whether it is set up. Setting a platform
    /// up is not offered yet.
    public struct MessagingChannelsView: View {
        @State private var model: MessagingServerModel

        public init(connections: ConnectionsModel) {
            _model = State(
                initialValue: MessagingServerModel(
                    connections: connections, read: { try await $0.messagingPlatforms().statusLines }))
        }

        init(model: MessagingServerModel) {
            _model = State(initialValue: model)
        }

        public var body: some View {
            List {
                Section {
                    MessagingStatusList(model: model)
                } header: {
                    Text("Platforms")
                } footer: {
                    Text("Pull down to refresh.")
                }
                MessagingStatusRows(model: model)
            }
            .navigationTitle("Channels")
            .refreshable { await model.refresh() }
            .task { await model.refresh() }
        }
    }

    /// Settings > Messaging > Pairing requests. Shows how many requests wait and how many users are approved. Approves a
    /// user by the code the bot sent, revokes a user, or clears the pending requests. Revoke and clear ask first.
    public struct PairingRequestsView: View {
        @State private var model: MessagingServerModel
        @State private var approvePlatform = ""
        @State private var approveCode = ""
        @State private var revokePlatform = ""
        @State private var revokeUserId = ""
        @State private var pendingRevoke: PairingRevoke?
        @State private var showsClear = false

        public init(connections: ConnectionsModel) {
            _model = State(
                initialValue: MessagingServerModel(
                    connections: connections, read: { try await $0.pairingRequests().statusLines }))
        }

        init(model: MessagingServerModel) {
            _model = State(initialValue: model)
        }

        public var body: some View {
            List {
                Section {
                    MessagingStatusList(model: model)
                } header: {
                    Text("Requests")
                } footer: {
                    Text("Counts only. Pull down to refresh.")
                }
                MessagingStatusRows(model: model)
                approveSection
                revokeSection
                Section {
                    Button("Clear pending requests…", role: .destructive) { showsClear = true }
                        .accessibilityIdentifier("pairing.clear")
                } footer: {
                    Text("Clears the requests that wait for approval.")
                }
            }
            .navigationTitle("Pairing requests")
            .refreshable { await model.refresh() }
            .task { await model.refresh() }
            .confirmationDialog(
                "Revoke access?",
                isPresented: Binding(get: { pendingRevoke != nil }, set: { if !$0 { pendingRevoke = nil } }),
                titleVisibility: .visible, presenting: pendingRevoke
            ) { revoke in
                Button("Revoke access", role: .destructive) {
                    Task { await model.perform("Access revoked.") { try await $0.revokePairing(revoke) } }
                }
            } message: { revoke in
                Text("User \(revoke.userId) on \(revoke.platform) loses access.")
            }
            .confirmationDialog("Clear pending requests?", isPresented: $showsClear, titleVisibility: .visible) {
                Button("Clear pending requests", role: .destructive) {
                    Task { await model.perform("Pending requests cleared.") { try await $0.clearPendingPairing() } }
                }
            } message: {
                Text("The requests that wait for approval are cleared.")
            }
        }

        private var approveSection: some View {
            Section {
                TextField("Platform, such as telegram", text: $approvePlatform)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("pairing.approve.platform")
                TextField("Code the bot sent", text: $approveCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("pairing.approve.code")
                Button("Approve") {
                    let approve = PairingApprove(
                        platform: approvePlatform.messagingTrimmed, code: approveCode.messagingTrimmed)
                    Task { await model.perform("Approved.") { try await $0.approvePairing(approve) } }
                }
                .disabled(approvePlatform.messagingTrimmed.isEmpty || approveCode.messagingTrimmed.isEmpty)
                .accessibilityIdentifier("pairing.approve")
            } header: {
                Text("Approve a code")
            }
        }

        private var revokeSection: some View {
            Section {
                TextField("Platform, such as telegram", text: $revokePlatform)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("pairing.revoke.platform")
                TextField("User id on that platform", text: $revokeUserId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("pairing.revoke.user")
                Button("Revoke access…", role: .destructive) {
                    pendingRevoke = PairingRevoke(
                        platform: revokePlatform.messagingTrimmed, userId: revokeUserId.messagingTrimmed)
                }
                .disabled(revokePlatform.messagingTrimmed.isEmpty || revokeUserId.messagingTrimmed.isEmpty)
                .accessibilityIdentifier("pairing.revoke")
            } header: {
                Text("Revoke a user")
            }
        }
    }

    /// Settings > Messaging > Webhooks. Shows whether webhooks are on, where they listen and how many there are. Status
    /// only. Turns webhooks on, creates a webhook, and enables, disables or deletes one by its name. Delete asks first.
    public struct WebhookListView: View {
        @State private var model: MessagingServerModel
        @State private var name = ""
        @State private var pendingDelete: String?

        public init(connections: ConnectionsModel) {
            _model = State(
                initialValue: MessagingServerModel(
                    connections: connections, read: { try await $0.webhooks().statusLines }))
        }

        init(model: MessagingServerModel) {
            _model = State(initialValue: model)
        }

        public var body: some View {
            List {
                Section {
                    MessagingStatusList(model: model)
                } header: {
                    Text("Webhooks")
                } footer: {
                    Text("Status only. Pull down to refresh.")
                }
                MessagingStatusRows(model: model)
                Section {
                    Button("Enable webhooks") {
                        Task { await model.perform("Webhooks are on.") { try await $0.enableWebhooks() } }
                    }
                    .accessibilityIdentifier("webhooks.enable")
                    NavigationLink {
                        WebhookCreateView(model: model)
                    } label: {
                        Label("New webhook", systemImage: "plus")
                    }
                    .accessibilityIdentifier("webhooks.new")
                } header: {
                    Text("Add")
                }
                changeByNameSection
            }
            .navigationTitle("Webhooks")
            .refreshable { await model.refresh() }
            .task { await model.refresh() }
            .confirmationDialog(
                "Delete webhook?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible, presenting: pendingDelete
            ) { webhook in
                Button("Delete webhook", role: .destructive) {
                    Task { await model.perform("Webhook deleted.") { try await $0.deleteWebhook(name: webhook) } }
                }
            } message: { webhook in
                Text("\"\(webhook)\" is deleted from the server.")
            }
        }

        private var changeByNameSection: some View {
            Section {
                TextField("Webhook name", text: $name)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("webhooks.name")
                HStack {
                    Button("Enable") {
                        let webhook = name.messagingTrimmed
                        Task {
                            await model.perform("Webhook enabled.") {
                                try await $0.setWebhookEnabled(name: webhook, true)
                            }
                        }
                    }
                    Button("Disable") {
                        let webhook = name.messagingTrimmed
                        Task {
                            await model.perform("Webhook disabled.") {
                                try await $0.setWebhookEnabled(name: webhook, false)
                            }
                        }
                    }
                }
                .buttonStyle(.borderless)
                .disabled(name.messagingTrimmed.isEmpty)
                Button("Delete…", role: .destructive) { pendingDelete = name.messagingTrimmed }
                    .disabled(name.messagingTrimmed.isEmpty)
                    .accessibilityIdentifier("webhooks.delete")
            } header: {
                Text("Change one by name")
            } footer: {
                Text("Type the webhook's name. This screen does not list names.")
            }
        }
    }

    /// The error or the notice of the last request, as list rows.
    private struct MessagingStatusRows: View {
        let model: MessagingServerModel

        var body: some View {
            if let errorText = model.errorText {
                Label(errorText, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(HermesColor.destructive)
                    .accessibilityIdentifier("messaging.error")
            }
            if let noticeText = model.noticeText {
                Label(noticeText, systemImage: "checkmark.circle")
                    .foregroundStyle(HermesColor.secondaryText)
                    .accessibilityIdentifier("messaging.notice")
            }
        }
    }

    /// The status rows of the last list: a title, and the status under it at the trailing edge. Shows a spinner while
    /// the first load runs.
    private struct MessagingStatusList: View {
        let model: MessagingServerModel

        var body: some View {
            if let lines = model.lines {
                ForEach(lines.indices, id: \.self) { index in
                    HStack {
                        Text(lines[index].title)
                        Spacer()
                        Text(lines[index].detail)
                            .foregroundStyle(HermesColor.secondaryText)
                            .multilineTextAlignment(.trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            } else if model.isLoading {
                ProgressView()
            } else {
                Text("Nothing loaded yet.")
                    .font(HermesFont.footnote)
                    .foregroundStyle(HermesColor.secondaryText)
            }
        }
    }

    private enum MessagingPreviewData {
        static let platforms: [MessagingStatusLine] = [
            MessagingStatusLine(title: "Telegram", detail: "disabled, not set up"),
            MessagingStatusLine(title: "WhatsApp", detail: "disabled, not set up"),
        ]
        static let pairing: [MessagingStatusLine] = [
            MessagingStatusLine(title: "Waiting for approval", detail: "1"),
            MessagingStatusLine(title: "Approved users", detail: "0"),
        ]
        static let webhooks: [MessagingStatusLine] = [
            MessagingStatusLine(title: "Webhooks", detail: "On"),
            MessagingStatusLine(title: "Base URL", detail: "http://localhost:8644"),
            MessagingStatusLine(title: "Subscriptions", detail: "1"),
        ]
    }

    #Preview("Channels, outer", traits: .fixedLayout(width: 466, height: 678)) {
        NavigationStack { MessagingChannelsView(model: .preview(lines: MessagingPreviewData.platforms)) }
    }

    #Preview("Channels, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        NavigationStack { MessagingChannelsView(model: .preview(lines: MessagingPreviewData.platforms)) }
    }

    #Preview("Channels, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        NavigationStack { MessagingChannelsView(model: .preview(lines: MessagingPreviewData.platforms)) }
    }

    #Preview("Channels, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        NavigationStack { MessagingChannelsView(model: .preview(lines: MessagingPreviewData.platforms)) }
    }

    #Preview("Pairing requests, outer", traits: .fixedLayout(width: 466, height: 678)) {
        NavigationStack { PairingRequestsView(model: .preview(lines: MessagingPreviewData.pairing)) }
    }

    #Preview("Pairing requests, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        NavigationStack { PairingRequestsView(model: .preview(lines: MessagingPreviewData.pairing)) }
    }

    #Preview("Pairing requests, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        NavigationStack { PairingRequestsView(model: .preview(lines: MessagingPreviewData.pairing)) }
    }

    #Preview("Pairing requests, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        NavigationStack { PairingRequestsView(model: .preview(lines: MessagingPreviewData.pairing)) }
    }

    #Preview("Webhooks, outer", traits: .fixedLayout(width: 466, height: 678)) {
        NavigationStack { WebhookListView(model: .preview(lines: MessagingPreviewData.webhooks)) }
    }

    #Preview("Webhooks, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        NavigationStack { WebhookListView(model: .preview(lines: MessagingPreviewData.webhooks)) }
    }

    #Preview("Webhooks, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        NavigationStack { WebhookListView(model: .preview(lines: MessagingPreviewData.webhooks)) }
    }

    #Preview("Webhooks, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        NavigationStack { WebhookListView(model: .preview(lines: MessagingPreviewData.webhooks)) }
    }
#endif
