#if canImport(UIKit)
    import HermesKit
    import SwiftUI
    import UIKit
    import VisionKit

    /// The guided setup for a computer that runs Hermes (plans/guided-setup): set up the computer with the prompt, scan
    /// the code or type the address, sign in when the server asks, check each link, then save. The fields and the test are
    /// the gateway form's, so the wizard and Enter an address behave the same.
    public struct GatewaySetupWizard: View {
        /// The steps in order. Sign-in only appears when the server asks for a password.
        enum Step: Equatable {
            case computer
            case find
            case signIn
            case check
            case done
        }

        private let connections: ConnectionsModel
        private let onFinish: () -> Void
        @State private var form = ConnectionFormModel(mode: .gateway)
        @State private var step = Step.computer
        @State private var typedAddress = ""
        @State private var findProblem: String?
        @State private var isReaching = false
        @State private var copied = false
        @State private var saveProblem: String?
        @AppStorage("hermes.localNetworkExplained") private var localNetworkExplained = false

        /// `onFinish` runs when the wizard closes: after a save, or when the user cancels.
        public init(connections: ConnectionsModel, onFinish: @escaping () -> Void) {
            self.connections = connections
            self.onFinish = onFinish
        }

        public var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        content
                    }
                    .padding(24)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                }
                .background(HermesColor.groupedBackground)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { onFinish() }
                            .accessibilityIdentifier("setup.cancel")
                    }
                }
                .sheet(isPresented: explainerBinding) {
                    LocalNetworkExplainer { explainerContinued() }
                }
            }
        }

        private var title: String {
            switch step {
            case .computer: "Set up on your computer"
            case .find: "Find the server"
            case .signIn: "Sign in"
            case .check: "Check the connection"
            case .done: "Save the server"
            }
        }

        @ViewBuilder
        private var content: some View {
            switch step {
            case .computer: computerStep
            case .find: findStep
            case .signIn: signInStep
            case .check: checkStep
            case .done: doneStep
            }
        }

        // MARK: Steps

        private var computerStep: some View {
            Group {
                Text("Hermes runs on your computer and stays on while this iPhone is away. Tailscale connects the two.")
                    .foregroundStyle(HermesColor.secondaryText)
                HermesCard {
                    Text("Copy the setup prompt").font(HermesFont.headline)
                    Text(
                        "Paste it into the Hermes agent on your computer. It sets up Hermes for this iPhone and "
                            + "prints a code to scan."
                    )
                    .font(HermesFont.footnote)
                    .foregroundStyle(HermesColor.secondaryText)
                    Button {
                        copyPrompt()
                    } label: {
                        Label(copied ? "Copied" : "Copy setup prompt", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(HermesButtonStyle(.tinted))
                    .accessibilityIdentifier("setup.copyPrompt")
                    ShareLink(item: GatewaySetup.prompt) {
                        Label("Share prompt", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(HermesButtonStyle(.tinted))
                }
                HermesCard {
                    Text("Before you start").font(HermesFont.headline)
                    Text(
                        "Turn on Tailscale on this iPhone and on the computer. In the Tailscale admin console, "
                            + "turn on MagicDNS and HTTPS Certificates once."
                    )
                    .font(HermesFont.footnote)
                    .foregroundStyle(HermesColor.secondaryText)
                }
                Button("Next") { step = .find }
                    .buttonStyle(HermesButtonStyle(.primary))
                    .accessibilityIdentifier("setup.next")
            }
        }

        private var findStep: some View {
            Group {
                Text("Scan the code the setup prints. You can also type the address it shows.")
                    .foregroundStyle(HermesColor.secondaryText)
                scanner
                TextField("https://computer.tailnet-name.ts.net", text: $typedAddress)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(HermesFont.code)
                    .accessibilityIdentifier("setup.address")
                if let findProblem {
                    Label(findProblem, systemImage: "xmark.octagon.fill")
                        .foregroundStyle(HermesColor.destructive)
                }
                if isReaching {
                    ProgressView("Reaching the server…")
                } else {
                    Button("Continue") { useTypedAddress() }
                        .buttonStyle(HermesButtonStyle(.primary))
                        .disabled(typedAddress.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("setup.findNext")
                }
                Button("Start over") { step = .computer }
                    .buttonStyle(HermesButtonStyle(.secondary))
                    .accessibilityIdentifier("setup.back")
            }
        }

        private var signInStep: some View {
            Group {
                if form.signInMethod == .password {
                    Text("This server asks for a user name and password. The setup prompt printed them.")
                        .foregroundStyle(HermesColor.secondaryText)
                    HermesCard {
                        TextField("User name", text: field(\.username))
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("setup.username")
                        SecureField("Password", text: field(\.password))
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.password)
                            .accessibilityIdentifier("setup.password")
                        Toggle("Remember password on this iPhone", isOn: field(\.remembersPassword))
                    }
                    Button("Check connection") { startCheck() }
                        .buttonStyle(HermesButtonStyle(.primary))
                        .disabled(form.username.isEmpty || form.password.isEmpty)
                        .accessibilityIdentifier("setup.signIn")
                } else {
                    Text(
                        "This server signs in another way. Use Enter an address on the first screen to sign in "
                            + "with a browser."
                    )
                    .foregroundStyle(HermesColor.secondaryText)
                }
                Button("Change address") { step = .find }
                    .buttonStyle(HermesButtonStyle(.secondary))
                    .accessibilityIdentifier("setup.changeAddress")
            }
        }

        private var checkStep: some View {
            Group {
                if let note = GatewaySetup.loopbackNote(for: hint?.host) {
                    Label(note, systemImage: "iphone")
                        .foregroundStyle(HermesColor.statusWarning)
                        .accessibilityIdentifier("setup.loopbackNote")
                }
                HermesCard {
                    ForEach(GatewaySetup.Check.allCases, id: \.self) { check in
                        SetupCheckRow(check: check, status: rows[check] ?? .pending)
                    }
                }
                switch form.test {
                case .passed:
                    Text("The server answered, the sign-in worked and the live connection opened.")
                        .foregroundStyle(HermesColor.secondaryText)
                    Button("Continue") { step = .done }
                        .buttonStyle(HermesButtonStyle(.primary))
                        .accessibilityIdentifier("setup.continue")
                case .failed:
                    Button("Try again") { startCheck() }
                        .buttonStyle(HermesButtonStyle(.primary))
                        .accessibilityIdentifier("setup.retry")
                    if case .failed? = rows[.signIn], form.signInMethod == .password {
                        Button("Change password") { step = .signIn }
                            .buttonStyle(HermesButtonStyle(.secondary))
                            .accessibilityIdentifier("setup.changePassword")
                    }
                    Button("Change address") { step = .find }
                        .buttonStyle(HermesButtonStyle(.secondary))
                        .accessibilityIdentifier("setup.changeAddress")
                case .idle, .running:
                    ProgressView("Checking…")
                }
            }
        }

        private var doneStep: some View {
            Group {
                Text("The connection works. Save the server to use it on this iPhone.")
                    .foregroundStyle(HermesColor.secondaryText)
                HermesCard {
                    TextField("Name (optional)", text: field(\.name))
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("setup.name")
                }
                if let saveProblem {
                    Label(saveProblem, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(HermesColor.destructive)
                }
                Button("Save server") { save() }
                    .buttonStyle(HermesButtonStyle(.primary))
                    .accessibilityIdentifier("setup.save")
            }
        }

        private var scanner: some View {
            Group {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    QRScannerView { text in useScanned(text) }
                        .clipShape(RoundedRectangle(cornerRadius: HermesMetrics.cardRadius, style: .continuous))
                        .frame(height: 300)
                } else {
                    ContentUnavailableView(
                        "Camera not available", systemImage: "camera",
                        description: Text("Type the address below instead."))
                }
            }
        }

        // MARK: Actions

        private func copyPrompt() {
            UIPasteboard.general.string = GatewaySetup.prompt
            copied = true
        }

        /// A code from the camera or from the typed field. A gateway code fills the form and goes on to the address check.
        private func useScanned(_ text: String) {
            guard let code = ConnectionQRCode(scanned: text) else {
                findProblem = "That code isn't a simplyHermes server code."
                return
            }
            switch code {
            case .gateway(let url, let name, let user):
                form.urlText = url
                if let name, form.name.isEmpty { form.name = name }
                if let user {
                    form.signInMethod = .password
                    form.username = user
                }
            case .ssh:
                findProblem = "That code is for an SSH server. Use Add SSH server instead."
                return
            }
            findProblem = nil
            typedAddress = form.urlText
            reachAddress()
        }

        private func useTypedAddress() {
            let text = typedAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            guard case .success = ConnectionAddress.parse(text) else {
                findProblem = "That isn't a server address. Try https://computer.tailnet-name.ts.net."
                return
            }
            findProblem = nil
            form.urlText = text
            reachAddress()
        }

        /// Reads what the address's server asks for. Then the wizard goes on to sign in, or straight to the check.
        private func reachAddress() {
            isReaching = true
            Task {
                await form.probeAddress(with: connections.services, localNetworkExplained: localNetworkExplained)
                isReaching = false
                if !form.showsLocalNetworkExplainer { afterProbe() }
            }
        }

        private func afterProbe() {
            if case .found(let found) = form.probe, found.authRequired {
                step = .signIn
            } else {
                startCheck()
            }
        }

        private func explainerContinued() {
            localNetworkExplained = true
            form.showsLocalNetworkExplainer = false
            reachAddress()
        }

        private func startCheck() {
            step = .check
            Task { await form.runTest(with: connections) }
        }

        /// Saves the server the same way the address form does. The first server saved becomes the active one.
        private func save() {
            do {
                try form.save(to: connections)
                onFinish()
            } catch let error as ConnectionSaveError {
                saveProblem = error.message
            } catch let error as ConnectionTestFailure {
                saveProblem = error.message
            } catch {
                saveProblem = "\(error)"
            }
        }

        // MARK: State

        /// Each check's status, from the form's test.
        private var rows: [GatewaySetup.Check: GatewaySetup.Status] {
            switch form.test {
            case .idle, .running:
                GatewaySetup.statuses(stage: form.testStage, failure: nil, passed: false, address: hint)
            case .passed:
                GatewaySetup.statuses(stage: form.testStage, failure: nil, passed: true, address: hint)
            case .failed(let failure):
                GatewaySetup.statuses(stage: form.testStage, failure: failure, passed: false, address: hint)
            }
        }

        /// The hints for the typed address. Off on the Simulator, where 127.0.0.1 is the Mac and CI relies on it.
        private var hint: GatewaySetup.Address? {
            #if targetEnvironment(simulator)
                return nil
            #else
                return GatewaySetup.Address(typed: form.urlText)
            #endif
        }

        private var explainerBinding: Binding<Bool> {
            Binding(get: { form.showsLocalNetworkExplainer }, set: { form.showsLocalNetworkExplainer = $0 })
        }

        /// A two-way binding to one field of the form.
        private func field<Value>(_ keyPath: ReferenceWritableKeyPath<ConnectionFormModel, Value>) -> Binding<Value> {
            Binding(get: { form[keyPath: keyPath] }, set: { form[keyPath: keyPath] = $0 })
        }
    }

    /// One check on the check step: its status, and for a failure what went wrong and what to try.
    struct SetupCheckRow: View {
        let check: GatewaySetup.Check
        let status: GatewaySetup.Status

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    icon
                        .frame(width: 24)
                    Text(check.title)
                        .font(HermesFont.body)
                    Spacer(minLength: 0)
                }
                if case .failed(let diagnosis) = status {
                    Text(diagnosis.message)
                        .font(HermesFont.footnote)
                        .foregroundStyle(HermesColor.destructive)
                    ForEach(diagnosis.fixes, id: \.self) { fix in
                        Text("• \(fix)")
                            .font(HermesFont.footnote)
                            .foregroundStyle(HermesColor.secondaryText)
                    }
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("setup.check.\(check)")
        }

        @ViewBuilder
        private var icon: some View {
            switch status {
            case .pending:
                Image(systemName: "circle")
                    .foregroundStyle(HermesColor.secondaryText)
            case .running:
                ProgressView()
                    .controlSize(.small)
            case .passed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(HermesColor.statusConnected)
            case .failed:
                Image(systemName: "xmark.octagon.fill")
                    .foregroundStyle(HermesColor.destructive)
            }
        }
    }

    /// True on the Simulator, where 127.0.0.1 is the Mac. Notes about this phone's own loopback are for devices only.
    enum SetupEnvironment {
        static var isSimulator: Bool {
            #if targetEnvironment(simulator)
                return true
            #else
                return false
            #endif
        }
    }

    #Preview("Setup, outer", traits: .fixedLayout(width: 466, height: 678)) {
        GatewaySetupWizard(connections: .preview([])) {}
    }

    #Preview("Setup, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        GatewaySetupWizard(connections: .preview([])) {}
    }

    #Preview("Setup, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        GatewaySetupWizard(connections: .preview([])) {}
    }

    #Preview("Setup, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        GatewaySetupWizard(connections: .preview([])) {}
    }
#endif
