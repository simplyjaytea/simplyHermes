#if canImport(UIKit)
    import HermesKit
    import SwiftUI
    import UIKit

    /// The SSH part of the form, as decided on the design canvas: server, key (generate or import, with the
    /// `authorized_keys` line to copy or share) and advanced options.
    struct SSHFormSections: View {
        @Bindable var form: ConnectionFormModel
        @State private var copied = false

        var body: some View {
            Section("Server") {
                TextField("Name (optional)", text: $form.name)
                    .accessibilityIdentifier("connection.name")
                TextField("Host", text: $form.host)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("connection.host")
                TextField("User", text: $form.sshUser)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("connection.user")
                LabeledContent("Port") {
                    TextField("22", text: $form.port)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("connection.port")
                }
            }

            Section {
                Picker("Key", selection: $form.keySource) {
                    ForEach(ConnectionFormModel.KeySource.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                switch form.keySource {
                case .generate: generatedKey
                case .importKey: importedKey
                }
            } header: {
                Text("Key")
            } footer: {
                Text(
                    form.keySource == .generate
                        ? "Add this line to ~/.ssh/authorized_keys on the server. The private key never leaves this iPhone."
                        : "Paste an OpenSSH private key (Ed25519 or RSA). It is stored in the Keychain on this iPhone only."
                )
            }

            Section("Advanced") {
                TextField("Path to hermes (optional)", text: $form.hermesPath)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(HermesFont.code)
                TextField("Hermes profile (optional)", text: $form.remoteProfile)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }

        @ViewBuilder
        private var generatedKey: some View {
            if let line = form.publicKeyLine {
                Text(line)
                    .font(HermesFont.codeSmall)
                    .textSelection(.enabled)
                    .lineLimit(4)
                    .accessibilityIdentifier("connection.publicKey")
                HStack(spacing: 12) {
                    Button {
                        UIPasteboard.general.string = line
                        copied = true
                    } label: {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(HermesButtonStyle(.tinted))
                    .hermesFeedback(.selection, trigger: copied)
                    ShareLink(item: line) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(HermesButtonStyle(.tinted))
                }
                .listRowSeparator(.hidden)
            }
            Button("Make a new key", role: .destructive) {
                form.generateKey()
                copied = false
            }
        }

        @ViewBuilder
        private var importedKey: some View {
            TextEditor(text: $form.importText)
                .font(HermesFont.codeSmall)
                .frame(minHeight: 120)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .overlay(alignment: .topLeading) {
                    if form.importText.isEmpty {
                        Text("-----BEGIN OPENSSH PRIVATE KEY-----")
                            .font(HermesFont.codeSmall)
                            .foregroundStyle(HermesColor.secondaryText)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityIdentifier("connection.privateKey")
            Button {
                form.importText = UIPasteboard.general.string ?? form.importText
            } label: {
                Label("Paste key", systemImage: "doc.on.clipboard")
            }
            SecureField("Passphrase (if the key has one)", text: $form.passphrase)
        }
    }

    /// The Test result row: progress, success with server details, or the failure in plain words.
    struct ConnectionTestStatus: View {
        let form: ConnectionFormModel
        let connections: ConnectionsModel

        var body: some View {
            Group {
                switch form.test {
                case .idle:
                    EmptyView()
                case .running(let step):
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(step.title).foregroundStyle(HermesColor.secondaryText)
                    }
                case .passed(let report):
                    passed(report)
                case .failed(.hostKeyChanged(let expected, let actual)):
                    HostKeyChangedCard(expected: expected, actual: actual) {
                        Task { await form.trustChangedKey(with: connections) }
                    }
                case .failed(let failure):
                    Label(failure.message, systemImage: "xmark.octagon.fill")
                        .foregroundStyle(HermesColor.destructive)
                        .accessibilityIdentifier("connection.testFailed")
                }
            }
            .hermesFeedback(.approved, trigger: isPassed)
            .hermesFeedback(.error, trigger: isFailed)
        }

        private var isPassed: Bool {
            if case .passed = form.test { return true }
            return false
        }

        private var isFailed: Bool {
            if case .failed = form.test { return true }
            return false
        }

        private func passed(_ report: ConnectionTestReport) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                Label("Connection works", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(HermesColor.statusConnected)
                    .font(HermesFont.body.weight(.semibold))
                    .accessibilityIdentifier("connection.testPassed")
                let details = [
                    report.serverVersion.map { "Hermes \($0)" },
                    report.signedInAs.map { "signed in as \($0)" },
                    report.acceptedHostKey.map { "key \($0.fingerprint)" },
                ]
                .compactMap { $0 }
                if !details.isEmpty {
                    Text(details.joined(separator: " · "))
                        .font(HermesFont.footnote)
                        .foregroundStyle(HermesColor.secondaryText)
                }
            }
        }
    }

    /// The server's key changed: both fingerprints, and the Face ID-gated override (design canvas row 4).
    struct HostKeyChangedCard: View {
        let expected: String
        let actual: String
        let onTrust: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Label("The server's key changed", systemImage: "exclamationmark.shield.fill")
                    .font(HermesFont.headline)
                    .foregroundStyle(HermesColor.destructive)
                Text(
                    "This can mean someone is intercepting the connection. Don't continue unless you reinstalled the server."
                )
                .font(HermesFont.footnote)
                fingerprint("Trusted", expected)
                fingerprint("Now", actual)
                Button("Trust the new key…", role: .destructive, action: onTrust)
                    .font(HermesFont.body.weight(.semibold))
                    .accessibilityIdentifier("connection.trustNewKey")
            }
            .padding(.vertical, 4)
        }

        private func fingerprint(_ label: String, _ value: String) -> some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(HermesFont.caption).foregroundStyle(HermesColor.secondaryText)
                Text(value).font(HermesFont.codeSmall).textSelection(.enabled)
            }
        }
    }

    /// First connect: show the server key's SHA256 fingerprint and ask (design canvas row 4).
    public struct HostKeyTrustSheet: View {
        let fingerprint: HostKeyFingerprint
        let onAnswer: (Bool) -> Void

        public init(fingerprint: HostKeyFingerprint, onAnswer: @escaping (Bool) -> Void) {
            self.fingerprint = fingerprint
            self.onAnswer = onAnswer
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                HermesSheetHeader("Trust this server?") { onAnswer(false) }
                Text(
                    "This is the first time simplyHermes connects to this server. Check that the fingerprint matches "
                        + "ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub on the server."
                )
                .font(HermesFont.subheadline)
                HermesCard {
                    Text(keyType).font(HermesFont.caption).foregroundStyle(HermesColor.secondaryText)
                    Text(fingerprint.fingerprint)
                        .font(HermesFont.code)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("hostKey.fingerprint")
                }
                Spacer(minLength: 0)
                Button("Trust and connect") { onAnswer(true) }
                    .buttonStyle(HermesButtonStyle(.primary))
                    .accessibilityIdentifier("hostKey.trust")
                Button("Cancel") { onAnswer(false) }
                    .buttonStyle(HermesButtonStyle(.secondary))
            }
            .padding(20)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .interactiveDismissDisabled()
        }

        private var keyType: String {
            String(fingerprint.openSSHKey.split(separator: " ").first ?? "ssh key")
        }
    }

    /// Shown once before iOS asks for Local Network access, so the system prompt is no surprise (plan 2.4).
    public struct LocalNetworkExplainer: View {
        let onContinue: () -> Void

        public init(onContinue: @escaping () -> Void) {
            self.onContinue = onContinue
        }

        public var body: some View {
            VStack(spacing: 18) {
                Image(systemName: "wifi.router")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(HermesColor.accent)
                    .padding(.top, 24)
                Text("Allow local network")
                    .font(HermesFont.glanceTitle)
                Text(
                    "Your server is on this network. iOS asks next whether simplyHermes may find and connect to "
                        + "devices on it. Tap Allow, or the app can't reach the server."
                )
                .multilineTextAlignment(.center)
                .foregroundStyle(HermesColor.secondaryText)
                Spacer(minLength: 0)
                Button("Continue", action: onContinue)
                    .buttonStyle(HermesButtonStyle(.primary))
                    .accessibilityIdentifier("localNetwork.continue")
            }
            .padding(24)
            .presentationDetents([.medium])
        }
    }
#endif
