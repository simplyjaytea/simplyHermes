#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    extension ConnectionFormModel: Identifiable {}

    /// First launch with no saved server: pick a gateway URL, SSH or a QR code (WP-22).
    public struct WelcomeView: View {
        private let connections: ConnectionsModel
        @State private var form: ConnectionFormModel?
        @State private var showsScanner = false

        public init(connections: ConnectionsModel) {
            self.connections = connections
        }

        public var body: some View {
            ScrollView {
                VStack(spacing: 28) {
                    header
                    VStack(spacing: 12) {
                        Button {
                            form = ConnectionFormModel(mode: .gateway)
                        } label: {
                            Label("Add gateway URL", systemImage: "globe")
                        }
                        .buttonStyle(HermesButtonStyle(.primary))
                        .accessibilityIdentifier("welcome.addGateway")
                        Button {
                            form = ConnectionFormModel(mode: .ssh)
                        } label: {
                            Label("Add SSH server", systemImage: "terminal")
                        }
                        .buttonStyle(HermesButtonStyle(.secondary))
                        .accessibilityIdentifier("welcome.addSSH")
                        Button {
                            showsScanner = true
                        } label: {
                            Label("Scan QR code", systemImage: "qrcode.viewfinder")
                        }
                        .buttonStyle(HermesButtonStyle(.tinted))
                        .accessibilityIdentifier("welcome.scan")
                    }
                    .frame(maxWidth: 420)
                    HermesCard {
                        Text("Which one?").font(HermesFont.headline)
                        Text(
                            "Gateway URL: Hermes runs hermes serve on your network, over Tailscale or behind a proxy.\n"
                                + "SSH: the app logs in to a computer and starts Hermes itself."
                        )
                        .font(HermesFont.footnote)
                        .foregroundStyle(HermesColor.secondaryText)
                    }
                    .frame(maxWidth: 420)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .background(HermesColor.groupedBackground)
            .sheet(item: $form) { form in
                ConnectionFormView(form: form, connections: connections) { _ in self.form = nil }
                    .interactiveDismissDisabled(form.isTesting)
            }
            .sheet(isPresented: $showsScanner) {
                QRScanSheet { code in
                    showsScanner = false
                    form = ConnectionFormModel(scanned: code)
                }
            }
        }

        private var header: some View {
            VStack(spacing: 14) {
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(HermesColor.onAccent)
                    .frame(width: 88, height: 88)
                    .background(HermesColor.accent.gradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .padding(.top, 32)
                Text("Welcome to simplyHermes")
                    .font(HermesFont.glanceTitle)
                    .multilineTextAlignment(.center)
                Text("Connect to your Hermes server to start chatting.")
                    .font(HermesFont.body)
                    .foregroundStyle(HermesColor.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
    }

    /// Settings > Servers: every saved connection, add, edit, delete and pick the active one.
    public struct ServerListView: View {
        private let connections: ConnectionsModel
        @State private var form: ConnectionFormModel?
        @State private var showsScanner = false
        @State private var pendingDelete: ServerConnection?

        public init(connections: ConnectionsModel) {
            self.connections = connections
        }

        public var body: some View {
            List {
                Section {
                    ForEach(connections.connections) { connection in
                        Button {
                            edit(connection)
                        } label: {
                            ServerRow(connection: connection, isActive: connection.id == connections.active?.id)
                        }
                        .tint(HermesColor.primaryText)
                        .swipeActions {
                            Button("Delete", role: .destructive) { pendingDelete = connection }
                        }
                        .contextMenu {
                            Button("Use this server", systemImage: "checkmark") { connections.setActive(connection.id) }
                            Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = connection }
                        }
                    }
                } footer: {
                    Text("Tap a server to edit it or run Test again. Swipe left to delete.")
                }
            }
            .navigationTitle("Servers")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    AddServerMenu(onPick: { form = $0 }, onScan: { showsScanner = true })
                }
            }
            .overlay {
                if connections.isEmpty {
                    ContentUnavailableView(
                        "No servers", systemImage: "server.rack", description: Text("Add one with +."))
                }
            }
            .sheet(item: $form) { form in
                ConnectionFormView(form: form, connections: connections) { _ in self.form = nil }
                    .interactiveDismissDisabled(form.isTesting)
            }
            .sheet(isPresented: $showsScanner) {
                QRScanSheet { code in
                    showsScanner = false
                    form = ConnectionFormModel(scanned: code)
                }
            }
            .confirmationDialog(
                "Delete \(pendingDelete?.name ?? "server")?", isPresented: deleteBinding, titleVisibility: .visible,
                presenting: pendingDelete
            ) { connection in
                Button("Delete server and its keys", role: .destructive) { connections.delete(connection.id) }
            } message: { _ in
                Text("Its password, token or SSH key is removed from this iPhone. This can't be undone.")
            }
        }

        private var deleteBinding: Binding<Bool> {
            Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
        }

        private func edit(_ connection: ServerConnection) {
            Task {
                guard let secrets = await connections.secrets(for: connection, reason: "Edit \(connection.name)")
                else { return }
                form = ConnectionFormModel(editing: connection, secrets: secrets)
            }
        }
    }

    /// The + menu: gateway, SSH or QR code.
    struct AddServerMenu: View {
        let onPick: (ConnectionFormModel) -> Void
        let onScan: () -> Void

        var body: some View {
            Menu {
                Button("Gateway URL", systemImage: "globe") { onPick(ConnectionFormModel(mode: .gateway)) }
                Button("SSH server", systemImage: "terminal") { onPick(ConnectionFormModel(mode: .ssh)) }
                Button("Scan QR code", systemImage: "qrcode.viewfinder", action: onScan)
            } label: {
                Label("Add server", systemImage: "plus")
            }
            .accessibilityIdentifier("servers.add")
        }
    }

    /// One saved server in a list.
    struct ServerRow: View {
        let connection: ServerConnection
        let isActive: Bool

        var body: some View {
            HStack(spacing: 12) {
                Image(systemName: connection.isSSH ? "terminal" : "globe")
                    .foregroundStyle(HermesColor.accent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(connection.name).font(HermesFont.body.weight(.semibold))
                        if connection.requiresUnlock {
                            Image(systemName: "faceid")
                                .font(HermesFont.caption)
                                .foregroundStyle(HermesColor.secondaryText)
                                .accessibilityLabel(Text("Face ID"))
                        }
                    }
                    Text(connection.address)
                        .font(HermesFont.codeSmall)
                        .foregroundStyle(HermesColor.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if isActive {
                    Image(systemName: "checkmark")
                        .foregroundStyle(HermesColor.accent)
                        .accessibilityLabel(Text("In use"))
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("server.\(connection.name)")
        }
    }

    /// The server menu in the chat list and sidebar: switch servers fast, or open Settings > Servers.
    public struct ServerSwitcher: View {
        private let connections: ConnectionsModel
        private let onManage: () -> Void

        public init(connections: ConnectionsModel, onManage: @escaping () -> Void) {
            self.connections = connections
            self.onManage = onManage
        }

        public var body: some View {
            Menu {
                ForEach(connections.connections) { connection in
                    Button {
                        connections.setActive(connection.id)
                    } label: {
                        if connection.id == connections.active?.id {
                            Label(connection.name, systemImage: "checkmark")
                        } else {
                            Text(connection.name)
                        }
                    }
                }
                Divider()
                Button("Manage servers…", systemImage: "server.rack", action: onManage)
            } label: {
                HStack(spacing: 4) {
                    Circle()
                        .fill(connections.active == nil ? HermesColor.statusOffline : HermesColor.statusConnected)
                        .frame(width: 8, height: 8)
                    Text(connections.active?.name ?? "No server")
                        .font(HermesFont.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down").font(HermesFont.caption)
                }
            }
            .accessibilityIdentifier("serverSwitcher")
        }
    }

    /// The Settings section until WP-53 fills in the rest: Servers first.
    public struct SettingsHome: View {
        private let connections: ConnectionsModel

        public init(connections: ConnectionsModel) {
            self.connections = connections
        }

        public var body: some View {
            List {
                Section("Connection") {
                    NavigationLink {
                        ServerListView(connections: connections)
                    } label: {
                        LabeledContent {
                            Text("\(connections.connections.count)")
                        } label: {
                            Label("Servers", systemImage: "server.rack")
                        }
                    }
                    .accessibilityIdentifier("settings.servers")
                }
                Section {
                    Text("More settings arrive in WP-53.")
                        .foregroundStyle(HermesColor.secondaryText)
                }
            }
            .navigationTitle("Settings")
        }
    }

    #Preview("Welcome, outer", traits: .fixedLayout(width: 466, height: 678)) {
        WelcomeView(connections: .preview([]))
    }

    #Preview("Welcome, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        WelcomeView(connections: .preview([]))
    }

    #Preview("Welcome, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        WelcomeView(connections: .preview([]))
    }

    #Preview("Welcome, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        WelcomeView(connections: .preview([]))
    }

    #Preview("Servers, outer", traits: .fixedLayout(width: 466, height: 678)) {
        NavigationStack { ServerListView(connections: .preview()) }
    }

    #Preview("Gateway form, outer", traits: .fixedLayout(width: 466, height: 678)) {
        let form = ConnectionFormModel(mode: .gateway)
        form.urlText = "http://192.168.1.20:9119"
        return ConnectionFormView(form: form, connections: .preview()) { _ in }
    }

    #Preview("SSH form, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        ConnectionFormView(form: ConnectionFormModel(mode: .ssh), connections: .preview()) { _ in }
    }
#endif
