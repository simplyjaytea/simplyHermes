#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// Add or edit one connection: one Settings-style form for a gateway URL or an SSH host (WP-22).
    public struct ConnectionFormView: View {
        @Environment(\.hermesPalette) private var palette
        @Bindable private var form: ConnectionFormModel
        private let connections: ConnectionsModel
        private let onDone: (ServerConnection?) -> Void

        @State private var saveError: String?
        /// True when the explainer was opened by Test, so its Continue runs the test after the probe.
        @State private var testAfterExplainer = false
        /// True when the explainer was opened by Connect, so its Continue connects after the probe.
        @State private var connectAfterExplainer = false
        /// True from the Connect press until it has passed and saved, or failed.
        @State private var connecting = false
        @AppStorage("hermes.localNetworkExplained") private var localNetworkExplained = false

        /// `onDone` gets the saved connection, or nil when the user cancelled.
        public init(
            form: ConnectionFormModel, connections: ConnectionsModel,
            onDone: @escaping (ServerConnection?) -> Void
        ) {
            self.form = form
            self.connections = connections
            self.onDone = onDone
        }

        public var body: some View {
            NavigationStack {
                Form {
                    switch form.mode {
                    case .gateway:
                        GatewayFormSections(
                            form: form, connections: connections, localNetworkExplained: localNetworkExplained,
                            onSignedIn: usesConnectButton ? { startConnect() } : nil)
                    case .ssh: SSHFormSections(form: form)
                    }
                    if usesConnectButton { connectSection }
                    securitySection
                    if !usesConnectButton { testSection }
                    if let saveError {
                        Section {
                            Label(saveError, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(palette.errorText)
                        }
                        .hermesListRows()
                    }
                }
                .hermesThemedList()
                .hermesKeyboardDismissOnScroll()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .sheet(item: trustBinding) { pending in
                    HostKeyTrustSheet(fingerprint: pending.fingerprint) { form.answerTrust($0) }
                }
                .sheet(isPresented: $form.showsLocalNetworkExplainer, onDismiss: forgetTestAfterExplainer) {
                    LocalNetworkExplainer {
                        localNetworkExplained = true
                        form.showsLocalNetworkExplainer = false
                        let runsTest = testAfterExplainer
                        let connects = connectAfterExplainer
                        Task {
                            await form.probeAddress(with: connections.services, localNetworkExplained: true)
                            if connects {
                                await connect(localNetworkExplained: true)
                            } else if runsTest {
                                await form.runTest(with: connections)
                            }
                        }
                    }
                }
            }
        }

        /// A new gateway connects in one press. An edited gateway and SSH keep Test and Save.
        private var usesConnectButton: Bool { form.mode == .gateway && form.existingID == nil }

        private var title: String {
            switch (form.mode, form.existingID == nil) {
            case (.gateway, true): "Add gateway"
            case (.ssh, true): "Add SSH server"
            case (_, false): "Edit server"
            }
        }

        @ToolbarContentBuilder
        private var toolbar: some ToolbarContent {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { onDone(nil) }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(form.missing != nil || form.isTesting)
                    .accessibilityIdentifier("connection.save")
            }
        }

        private var securitySection: some View {
            Section {
                Toggle("Require Face ID", isOn: $form.requiresUnlock)
                    .accessibilityIdentifier("connection.faceID")
            } header: {
                Text("Security")
            } footer: {
                if form.mode == .ssh {
                    Text(
                        form.pinnedHostKey == nil
                            ? "SSH gives full control of the server, so Face ID is on by default. "
                                + "The server's key is checked on first connect."
                            : "The server's key is trusted and checked on every connect.")
                } else {
                    Text("Ask for Face ID before connecting to this server.")
                }
            }
            .hermesListRows()
        }

        /// The one primary action for a new gateway: test the connection and, when it passes, save it.
        private var connectSection: some View {
            Section {
                Button {
                    startConnect()
                } label: {
                    HStack(spacing: 8) {
                        if connecting { ProgressView() }
                        Text("Connect")
                    }
                }
                .buttonStyle(HermesButtonStyle(.primary))
                .disabled(form.connectMissing != nil || form.isTesting || connecting)
                .accessibilityIdentifier("connection.connect")
                ConnectionTestStatus(form: form, connections: connections)
            } footer: {
                if let reason = form.connectMissing { Text(reason) }
            }
            .hermesListRows()
        }

        private var testSection: some View {
            Section {
                Button {
                    startTest()
                } label: {
                    Label("Test connection", systemImage: "bolt.horizontal.circle")
                }
                .disabled(form.missing != nil || form.isTesting)
                .accessibilityIdentifier("connection.test")
                ConnectionTestStatus(form: form, connections: connections)
            } footer: {
                if let missing = form.missing { Text(missing) }
            }
            .hermesListRows()
        }

        /// Clears the sheet binding by answering "don't trust", so a swiped-away sheet never hangs the test.
        private var trustBinding: Binding<ConnectionFormModel.PendingTrust?> {
            Binding(
                get: { form.pendingTrust },
                set: { newValue in if newValue == nil { form.answerTrust(false) } }
            )
        }

        /// Runs after the explainer closes, so a swiped-away explainer cannot run the test later.
        private func forgetTestAfterExplainer() {
            testAfterExplainer = false
            connectAfterExplainer = false
        }

        private func startConnect() {
            saveError = nil
            if needsLocalNetwork && !localNetworkExplained {
                connectAfterExplainer = true
                form.showsLocalNetworkExplainer = true
            } else {
                Task { await connect(localNetworkExplained: localNetworkExplained) }
            }
        }

        /// Tests the connection and saves it when the test passes, then closes the form. A failed test stays on the
        /// form, which shows the failing step.
        private func connect(localNetworkExplained explained: Bool) async {
            guard !connecting else { return }
            connecting = true
            defer { connecting = false }
            do {
                if let saved = try await form.connect(with: connections, localNetworkExplained: explained) {
                    onDone(saved)
                }
            } catch let error as ConnectionSaveError {
                saveError = error.message
            } catch let error as ConnectionTestFailure {
                saveError = error.message
            } catch {
                saveError = "\(error)"
            }
        }

        private func startTest() {
            if needsLocalNetwork && !localNetworkExplained {
                testAfterExplainer = true
                form.showsLocalNetworkExplainer = true
            } else {
                Task { await form.runTest(with: connections) }
            }
        }

        private var needsLocalNetwork: Bool {
            switch form.mode {
            case .gateway:
                return form.needsLocalNetwork
            case .ssh:
                return ConnectionAddress.classify(host: form.host.trimmingCharacters(in: .whitespaces))
                    == .privateNetwork
            }
        }

        private func save() {
            do {
                onDone(try form.save(to: connections))
            } catch let error as ConnectionSaveError {
                saveError = error.message
            } catch let error as ConnectionTestFailure {
                saveError = error.message
            } catch {
                saveError = "\(error)"
            }
        }
    }

    /// The gateway part of the form: address with the HTTP rule, and sign-in.
    struct GatewayFormSections: View {
        @Bindable var form: ConnectionFormModel
        let connections: ConnectionsModel
        /// False until the explainer has been shown once. A home address waits for it before the probe.
        let localNetworkExplained: Bool
        /// Called when a browser sign-in on a new server succeeds, so the form can go straight on to Connect.
        var onSignedIn: (() -> Void)?
        @FocusState private var addressFocused: Bool

        var body: some View {
            Section {
                TextField("192.168.1.20 or box.tailnet.ts.net", text: $form.urlText)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(HermesFont.code)
                    .focused($addressFocused)
                    .disabled(form.cloudOrigin != nil)
                    .accessibilityIdentifier("connection.url")
                TextField("Name (optional)", text: $form.name)
                    .accessibilityIdentifier("connection.name")
            } header: {
                Text("Server")
            } footer: {
                if let cloud = form.cloudOrigin {
                    Text("\(cloud.agentName) in \(cloud.organizationName). Hermes Cloud sets this address.")
                } else {
                    AddressFooter(address: form.address, adaptedNote: form.adaptedAddressNote)
                }
            }
            .hermesListRows()
            .task(id: form.urlText) {
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                await form.probeAddress(with: connections.services, localNetworkExplained: localNetworkExplained)
            }
            .task {
                // A new server starts with the address ready to type or paste into.
                guard form.existingID == nil, form.urlText.isEmpty else { return }
                try? await Task.sleep(for: .milliseconds(400))
                addressFocused = true
            }

            Section {
                SignInMethodSection(form: form, connections: connections, onSignedIn: onSignedIn)
            } header: {
                HStack {
                    Text("Sign in")
                    Spacer()
                    ProbeBadge(probe: form.probe)
                }
            }
            .hermesListRows()
        }
    }

    /// Under the address: the HTTP warning (plan Q14) or why the address is unusable.
    struct AddressFooter: View {
        @Environment(\.hermesPalette) private var palette
        let address: Result<ConnectionAddress.Parsed, ConnectionAddress.Problem>?
        var adaptedNote: String?

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                switch address {
                case nil:
                    Text("The address of hermes serve, with a path if it sits behind a proxy.")
                case .success(let parsed)?:
                    switch parsed.warning {
                    case .unencryptedLocal?:
                        Label(
                            "Plain HTTP: anyone on this network can read your chats. Use HTTPS, Tailscale or SSH if you can.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(palette.statusWarning)
                        .accessibilityIdentifier("connection.httpWarning")
                    case .unencryptedTailscale?:
                        Label(
                            "Plain HTTP over Tailscale. The tunnel encrypts it, so this is fine on your tailnet.",
                            systemImage: "lock.trianglebadge.exclamationmark"
                        )
                        .accessibilityIdentifier("connection.httpWarning")
                    case nil:
                        Text(parsed.endpoint.baseURL.absoluteString).font(HermesFont.codeSmall)
                    }
                case .failure(let problem)?:
                    Label(Self.message(for: problem), systemImage: "xmark.octagon.fill")
                        .foregroundStyle(palette.errorText)
                }
                if let adaptedNote {
                    Label(adaptedNote, systemImage: "arrow.triangle.branch")
                        .accessibilityIdentifier("connection.adaptedAddressNote")
                }
                if let note = loopbackNote {
                    Label(note, systemImage: "iphone")
                        .foregroundStyle(palette.statusWarning)
                        .accessibilityIdentifier("connection.loopbackNote")
                }
            }
        }

        /// The note for an address that points at this iPhone, which never reaches the computer. Devices only: on the
        /// Simulator, 127.0.0.1 is the Mac and the CI tests use it.
        private var loopbackNote: String? {
            guard !SetupEnvironment.isSimulator, case .success(let parsed)? = address else { return nil }
            return GatewaySetup.loopbackNote(for: parsed.hostClass)
        }

        static func message(for problem: ConnectionAddress.Problem) -> String {
            switch problem {
            case .empty, .invalid: "That isn't a server address. Try http://192.168.1.20:9119."
            case .unsupportedScheme(let scheme): "\(scheme):// isn't supported. Use http or https."
            case .httpNotAllowed(let host):
                "\(host) is on the internet, so plain HTTP isn't allowed. Use https://, Tailscale or SSH."
            }
        }
    }

    /// What the server said about sign-in before the user signed in.
    struct ProbeBadge: View {
        @Environment(\.hermesPalette) private var palette
        let probe: ConnectionFormModel.ProbeState

        var body: some View {
            switch probe {
            case .idle:
                EmptyView()
            case .checking:
                ProgressView().controlSize(.mini)
            case .found(let found):
                Text(found.authRequired ? "Required" : "Not needed")
                    .foregroundStyle(found.authRequired ? palette.secondaryText : palette.statusConnected)
            case .failed(let failure):
                Text(failure.message)
                    .foregroundStyle(palette.errorText)
                    .textSelection(.enabled)
            }
        }
    }

    extension ConnectionFormModel.BrowserState {
        var isSignedIn: Bool {
            if case .signedIn = self { return true }
            return false
        }
    }
#endif
