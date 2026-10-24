#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// Add or edit one connection: one Settings-style form for a gateway URL or an SSH host (WP-22).
    public struct ConnectionFormView: View {
        @Bindable private var form: ConnectionFormModel
        private let connections: ConnectionsModel
        private let onDone: (ServerConnection?) -> Void

        @State private var saveError: String?
        /// True when the explainer was opened by Test, so its Continue runs the test after the probe.
        @State private var testAfterExplainer = false
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
                            form: form, connections: connections, localNetworkExplained: localNetworkExplained)
                    case .ssh: SSHFormSections(form: form)
                    }
                    securitySection
                    testSection
                    if let saveError {
                        Section {
                            Label(saveError, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(HermesColor.destructive)
                        }
                    }
                }
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
                        Task {
                            await form.probeAddress(with: connections.services, localNetworkExplained: true)
                            if runsTest { await form.runTest(with: connections) }
                        }
                    }
                }
            }
        }

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

        var body: some View {
            Section {
                TextField("Name (optional)", text: $form.name)
                    .accessibilityIdentifier("connection.name")
                TextField("http://192.168.1.20:9119", text: $form.urlText)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(HermesFont.code)
                    .disabled(form.cloudOrigin != nil)
                    .accessibilityIdentifier("connection.url")
            } header: {
                Text("Server")
            } footer: {
                if let cloud = form.cloudOrigin {
                    Text("\(cloud.agentName) in \(cloud.organizationName). Hermes Cloud sets this address.")
                } else {
                    AddressFooter(address: form.address)
                }
            }
            .task(id: form.urlText) {
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                await form.probeAddress(with: connections.services, localNetworkExplained: localNetworkExplained)
            }

            Section {
                Picker("Sign in", selection: $form.signInMethod) {
                    ForEach(form.availableSignInMethods) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("connection.signIn")
                switch form.signInMethod {
                case .none:
                    EmptyView()
                case .browser:
                    BrowserSignInRows(form: form, connections: connections)
                case .password:
                    TextField("User name", text: $form.username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("connection.username")
                    SecureField("Password", text: $form.password)
                        .textContentType(.password)
                        .accessibilityIdentifier("connection.password")
                    Toggle("Remember password", isOn: $form.remembersPassword)
                case .token:
                    SecureField("Session token", text: $form.token)
                        .font(HermesFont.code)
                        .accessibilityIdentifier("connection.token")
                }
            } header: {
                HStack {
                    Text("Sign in")
                    Spacer()
                    ProbeBadge(probe: form.probe)
                }
            } footer: {
                SignInFooter(method: form.signInMethod, remembersPassword: form.remembersPassword)
            }
        }
    }

    /// Under the address: the HTTP warning (plan Q14) or why the address is unusable.
    struct AddressFooter: View {
        let address: Result<ConnectionAddress.Parsed, ConnectionAddress.Problem>?

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
                        .foregroundStyle(HermesColor.statusWarning)
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
                        .foregroundStyle(HermesColor.destructive)
                }
                if let note = loopbackNote {
                    Label(note, systemImage: "iphone")
                        .foregroundStyle(HermesColor.statusWarning)
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
        let probe: ConnectionFormModel.ProbeState

        var body: some View {
            switch probe {
            case .idle:
                EmptyView()
            case .checking:
                ProgressView().controlSize(.mini)
            case .found(let found):
                Text(found.authRequired ? "Required" : "Not needed")
                    .foregroundStyle(found.authRequired ? HermesColor.secondaryText : HermesColor.statusConnected)
            case .unreachable:
                Text("Server not found yet")
            }
        }
    }

    /// Browser sign-in: the provider when the server has several, the button, and the result.
    struct BrowserSignInRows: View {
        @Bindable var form: ConnectionFormModel
        let connections: ConnectionsModel

        var body: some View {
            if form.browserProviders.count > 1 {
                Picker("Provider", selection: $form.browserProvider) {
                    ForEach(form.browserProviders, id: \.name) { provider in
                        Text(provider.displayName ?? provider.name).tag(String?.some(provider.name))
                    }
                }
                .accessibilityIdentifier("connection.browserProvider")
            }
            Button {
                Task { await form.signInWithBrowser(with: connections.services) }
            } label: {
                HStack {
                    Text(form.browserState.isSignedIn ? "Sign in again" : "Sign in with browser")
                    Spacer()
                    if form.browserState == .signingIn { ProgressView() }
                }
            }
            .disabled(form.browserState == .signingIn)
            .accessibilityIdentifier("connection.browserSignIn")
            switch form.browserState {
            case .idle, .signingIn:
                EmptyView()
            case .signedIn(let user):
                Label(user.map { "Signed in as \($0)" } ?? "Signed in", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(HermesColor.statusConnected)
                    .accessibilityIdentifier("connection.browserSignedIn")
            case .failed(let message):
                Label(message, systemImage: "xmark.octagon.fill")
                    .foregroundStyle(HermesColor.destructive)
            }
        }
    }

    extension ConnectionFormModel.BrowserState {
        var isSignedIn: Bool {
            if case .signedIn = self { return true }
            return false
        }
    }

    struct SignInFooter: View {
        let method: ConnectionFormModel.SignInMethod
        let remembersPassword: Bool

        var body: some View {
            switch method {
            case .none:
                Text("This server doesn't ask for a sign-in.")
            case .browser:
                Text("Opens the server's sign-in page. The app keeps the sign-in in the Keychain on this iPhone only.")
            case .password:
                VStack(alignment: .leading, spacing: 6) {
                    Text(
                        remembersPassword
                            ? "Kept in the Keychain on this iPhone only, so the app can sign in again by itself."
                            : "Not stored. The app asks again when the server signs you out.")
                    Text(
                        "Tip: set HERMES_DASHBOARD_BASIC_AUTH_SECRET on the server, or every restart signs you out."
                    )
                    .accessibilityIdentifier("connection.basicAuthTip")
                }
            case .token:
                Text("Stored in the Keychain on this iPhone only.")
            }
        }
    }
#endif
