#if canImport(UIKit)
    import Foundation
    import HermesKit
    import HermesSSH
    import Observation

    /// The add or edit form for one connection: its fields, the Test button and host key trust (WP-22).
    @MainActor
    @Observable
    public final class ConnectionFormModel {
        public let mode: Mode
        public let existingID: UUID?
        private let createdAt: Date

        public var name = ""
        public var requiresUnlock: Bool

        // Gateway
        public var urlText = "" {
            didSet { if urlText != oldValue { invalidateTest() } }
        }
        public var signInMethod: SignInMethod = .none {
            didSet { if signInMethod != oldValue { invalidateTest() } }
        }
        public var username = "" {
            didSet { if username != oldValue { invalidateTest() } }
        }
        public var password = "" {
            didSet { if password != oldValue { invalidateTest() } }
        }
        public var token = "" {
            didSet { if token != oldValue { invalidateTest() } }
        }
        public var remembersPassword = false
        public private(set) var probe: ProbeState = .idle
        /// The provider for browser sign-in. Nil lets the server choose.
        public var browserProvider: String? {
            didSet { if browserProvider != oldValue { invalidateTest() } }
        }
        public private(set) var browserState: BrowserState = .idle
        private var browserResult: BrowserSignInResult?
        /// The server the browser sign-in belongs to. Tokens for another address are not used.
        private var browserServer: URL?
        /// Set when the entry came from Hermes Cloud (WP-17). The form keeps it, so editing never turns the agent into
        /// a plain gateway, and shows the address as read-only.
        public private(set) var cloudOrigin: CloudOrigin?

        // SSH
        public var host = "" {
            didSet { if host != oldValue { invalidateTest() } }
        }
        public var port = "22" {
            didSet { if port != oldValue { invalidateTest() } }
        }
        public var sshUser = "" {
            didSet { if sshUser != oldValue { invalidateTest() } }
        }
        public var keySource: KeySource = .generate {
            didSet { if keySource != oldValue { invalidateTest() } }
        }
        public private(set) var generatedKey: StoredSSHKey? {
            didSet { if generatedKey != oldValue { invalidateTest() } }
        }
        public private(set) var publicKeyLine: String?
        public var importText = "" {
            didSet { if importText != oldValue { invalidateTest() } }
        }
        public var passphrase = "" {
            didSet { if passphrase != oldValue { invalidateTest() } }
        }
        public var hermesPath = "" {
            didSet { if hermesPath != oldValue { invalidateTest() } }
        }
        public var remoteProfile = "" {
            didSet { if remoteProfile != oldValue { invalidateTest() } }
        }
        public private(set) var pinnedHostKey: String?
        private var ownershipID = SSHSettings.makeOwnershipID()

        public private(set) var test: TestState = .idle
        /// The IP endpoint Hermes answered on after it refused the typed name, and the typed URL it stands for.
        private var adaptedAddress: AdaptedAddress?

        private typealias TestRun = ConnectionTestRunTracker<TestTarget>.Run
        /// The test whose progress and result may still change this form. Empty before a test or after it ends.
        @ObservationIgnored private var testRuns = ConnectionTestRunTracker<TestTarget>()

        private struct AdaptedAddress {
            let typed: URL
            let endpoint: HermesEndpoint
        }
        /// The last step the test reported. It stays after the test ends, so a failure can say where it happened.
        public private(set) var testStage: ConnectionTestStep?
        public var pendingTrust: PendingTrust?
        @ObservationIgnored private var autoTrustFingerprint: String?

        /// A blank form.
        public init(mode: Mode) {
            self.mode = mode
            existingID = nil
            createdAt = Date()
            requiresUnlock = mode == .ssh
            if mode == .ssh { generateKey() }
        }

        /// A form for an existing connection and its secrets.
        public init(editing connection: ServerConnection, secrets: ConnectionSecrets) {
            existingID = connection.id
            createdAt = connection.createdAt
            name = connection.name
            requiresUnlock = connection.requiresUnlock
            switch connection.kind {
            case .gateway(let settings):
                mode = .gateway
                urlText = settings.endpoint.baseURL.absoluteString
                remembersPassword = settings.remembersPassword
                cloudOrigin = settings.cloud
                switch settings.signIn {
                case .none: signInMethod = .none
                case .password(let user):
                    signInMethod = .password
                    username = user
                case .sessionToken: signInMethod = .token
                case .browser(let provider):
                    signInMethod = .browser
                    browserProvider = provider
                    restoreBrowserSignIn(secrets, server: settings.endpoint.baseURL)
                }
                password = secrets.password ?? ""
                token = secrets.sessionToken ?? ""
            case .ssh(let settings):
                mode = .ssh
                host = settings.host
                port = String(settings.port)
                sshUser = settings.username
                hermesPath = settings.hermesPath ?? ""
                remoteProfile = settings.remoteProfile ?? ""
                pinnedHostKey = settings.pinnedHostKey
                ownershipID = settings.ownershipID
                switch secrets.sshKey {
                case .ed25519(let raw)?:
                    keySource = .generate
                    generatedKey = .ed25519(raw: raw)
                    publicKeyLine = SSHKeyMaterial.publicLine(for: .ed25519(raw: raw))
                case .openSSH(let text, let phrase)?:
                    keySource = .importKey
                    importText = text
                    passphrase = phrase ?? ""
                case nil:
                    generateKey()
                }
            }
        }

        /// Fills the form from a scanned QR code.
        public convenience init(scanned code: ConnectionQRCode) {
            switch code {
            case .gateway(let url, let name, let user):
                self.init(mode: .gateway)
                urlText = url
                self.name = name ?? ""
                if let user {
                    signInMethod = .password
                    username = user
                }
            case .ssh(let host, let port, let user):
                self.init(mode: .ssh)
                self.host = host
                self.port = String(port)
                sshUser = user
            }
        }

        // MARK: Derived state

        /// The parsed gateway address, or why it is unusable. Nil while the field is empty.
        public var address: Result<ConnectionAddress.Parsed, ConnectionAddress.Problem>? {
            let parsed = ConnectionAddress.parse(urlText)
            if case .failure(.empty) = parsed { return nil }
            return parsed
        }

        /// The first thing missing, or nil when the form can be tested and saved.
        public var missing: String? {
            switch mode {
            case .gateway:
                guard case .success? = address else { return "Enter a valid server address." }
                switch signInMethod {
                case .none: return nil
                case .browser: return browserSignInResult == nil ? "Sign in with the browser." : nil
                case .password: return username.isEmpty ? "Enter the user name." : nil
                case .token: return token.isEmpty ? "Paste the session token." : nil
                }
            case .ssh:
                if host.trimmingCharacters(in: .whitespaces).isEmpty { return "Enter the host." }
                if sshUser.isEmpty { return "Enter the user." }
                guard let portNumber = Int(port), (1...65535).contains(portNumber) else {
                    return "Enter a port from 1 to 65535."
                }
                if keySource == .importKey && importText.isEmpty { return "Paste the private key." }
                return nil
            }
        }

        /// The sign-in methods the picker offers: what the server supports, or all of them before it answers.
        /// The current choice stays listed so an edited connection never loses it.
        public var availableSignInMethods: [SignInMethod] {
            var methods: [SignInMethod]
            if case .found(let found) = probe {
                methods = Self.methods(for: found)
            } else {
                methods = SignInMethod.allCases
            }
            if !methods.contains(signInMethod) { methods.append(signInMethod) }
            return SignInMethod.allCases.filter(methods.contains)
        }

        /// The server's browser providers (OAuth, OIDC), for the provider picker.
        public var browserProviders: [AuthProviderInfo] {
            guard case .found(let found) = probe else { return [] }
            return found.signIn?.browserProviders ?? []
        }

        /// The endpoint to test and save: the typed one, or the IP address Hermes answered on instead.
        private func effectiveEndpoint(for parsed: ConnectionAddress.Parsed) -> HermesEndpoint {
            guard let adaptedAddress, adaptedAddress.typed == parsed.endpoint.baseURL else { return parsed.endpoint }
            return adaptedAddress.endpoint
        }

        /// Says which IP address the app uses when Hermes refused the typed name. Nil otherwise.
        public var adaptedAddressNote: String? {
            guard mode == .gateway, case .success(let parsed)? = address, let adaptedAddress,
                adaptedAddress.typed == parsed.endpoint.baseURL
            else { return nil }
            return HostFallback.note(typed: parsed.endpoint, adapted: adaptedAddress.endpoint)
        }

        private func rememberAdapted(_ endpoint: HermesEndpoint?, for typed: HermesEndpoint) {
            guard let endpoint else { return }
            adaptedAddress = AdaptedAddress(typed: typed.baseURL, endpoint: endpoint)
        }

        /// The browser sign-in, when it belongs to the address in the form.
        private var browserSignInResult: BrowserSignInResult? {
            guard case .success(let parsed)? = address, parsed.endpoint.baseURL == browserServer else { return nil }
            return browserResult
        }

        private static func methods(for found: ServerProbe) -> [SignInMethod] {
            guard found.authRequired else { return [.none] }
            if let options = found.signIn { return options.methods.map(SignInMethod.init) }
            return found.authProviders.contains("basic") ? [.password, .token] : [.token]
        }

        private static func recommended(for found: ServerProbe) -> SignInMethod {
            if let method = found.signIn?.recommended { return SignInMethod(method) }
            return found.authProviders.contains("basic") ? .password : .token
        }

        public var isTesting: Bool {
            if case .running = test { return true }
            return false
        }

        // MARK: Actions

        /// Makes a new Ed25519 key and shows its `authorized_keys` line.
        public func generateKey() {
            let made = SSHKeyMaterial.generate()
            generatedKey = made.key
            publicKeyLine = made.publicLine
            pinnedHostKey = nil
            test = .idle
        }

        /// Set when a home address waits for the Local Network explainer. The form shows the explainer.
        public var showsLocalNetworkExplainer = false

        /// True when the gateway address is a home address. iOS asks for Local Network access before such an address
        /// connects.
        public var needsLocalNetwork: Bool {
            guard mode == .gateway, case .success(let parsed)? = address else { return false }
            return parsed.needsLocalNetwork
        }

        /// Reads the server's sign-in needs and picks a matching sign-in method. A home address waits until the
        /// explainer has been shown, because the probe's first request is what makes iOS ask for access.
        public func probeAddress(with services: ConnectionServices, localNetworkExplained: Bool) async {
            guard mode == .gateway, case .success(let parsed)? = address else {
                probe = .idle
                return
            }
            if parsed.needsLocalNetwork && !localNetworkExplained {
                probe = .idle
                showsLocalNetworkExplainer = true
                return
            }
            probe = .checking
            let found: ServerProbe
            do {
                found = try await services.probe(parsed.endpoint)
            } catch {
                guard !Task.isCancelled, address == .success(parsed) else { return }
                let failure = (error as? ConnectionTestFailure) ?? GatewayConnectionTester.reachFailure(error)
                probe = .failed(failure)
                return
            }
            guard !Task.isCancelled, address == .success(parsed) else { return }
            rememberAdapted(found.adaptedEndpoint, for: parsed.endpoint)
            probe = .found(found)
            if !found.authRequired {
                signInMethod = .none
            } else if signInMethod == .none || !Self.methods(for: found).contains(signInMethod) {
                signInMethod = Self.recommended(for: found)
            }
            if browserProvider == nil, let only = found.signIn?.browserProviders, only.count == 1 {
                browserProvider = only[0].name
            }
        }

        /// Opens the browser sign-in and keeps its tokens or cookies for Save.
        public func signInWithBrowser(with services: ConnectionServices) async {
            guard case .success(let parsed)? = address else {
                browserState = .failed("Enter a valid server address.")
                return
            }
            var options: SignInOptions?
            if case .found(let found) = probe { options = found.signIn }
            let before = browserState
            browserState = .signingIn
            do {
                let result = try await services.browserSignIn.signIn(
                    endpoint: parsed.endpoint, options: options, provider: browserProvider)
                browserResult = result
                browserServer = parsed.endpoint.baseURL
                browserState = .signedIn(user: result.userID)
                invalidateTest()
            } catch NativeSignInError.cancelled {
                browserState = before == .signingIn ? .idle : before
            } catch {
                browserState = .failed(Self.browserMessage(for: error))
            }
        }

        private func restoreBrowserSignIn(_ secrets: ConnectionSecrets, server: URL) {
            if let tokens = secrets.nativeTokens {
                browserResult = .tokens(tokens)
            } else if let cookies = secrets.webCookies {
                browserResult = .cookies(cookies)
            }
            guard let browserResult else { return }
            browserServer = server
            browserState = .signedIn(user: browserResult.userID)
        }

        private static func browserMessage(for error: any Error) -> String {
            switch error {
            case NativeSignInError.codeRejected, NativeSignInError.stateMismatch, NativeSignInError.missingCode,
                RESTError.unauthorized:
                "The server didn't accept the sign-in. Try again."
            case NativeSignInError.sessionExpired:
                "The sign-in expired. Try again."
            case NativeSignInError.server(let detail):
                "The server refused the sign-in: \(detail)"
            default:
                "Couldn't sign in: \(error.localizedDescription)"
            }
        }

        /// The connection as typed. Throws a message for the form when a field is wrong.
        public func makeConnection() throws(ConnectionTestFailure) -> ServerConnection {
            if let missing { throw .invalidForm(missing) }
            let kind: ServerConnection.Kind
            switch mode {
            case .gateway:
                guard case .success(let parsed)? = address else { throw .invalidForm("Enter a valid server address.") }
                let signIn: GatewaySignIn =
                    switch signInMethod {
                    case .none: .none
                    case .browser: .browser(provider: browserProvider)
                    case .password: .password(username: username)
                    case .token: .sessionToken
                    }
                kind = .gateway(
                    GatewaySettings(
                        endpoint: effectiveEndpoint(for: parsed), signIn: signIn, remembersPassword: remembersPassword,
                        cloud: cloudOrigin))
            case .ssh:
                kind = .ssh(
                    SSHSettings(
                        host: host.trimmingCharacters(in: .whitespaces), port: Int(port) ?? 22, username: sshUser,
                        authentication: keySource == .generate ? .generatedKey : .importedKey,
                        pinnedHostKey: pinnedHostKey, hermesPath: hermesPath.isEmpty ? nil : hermesPath,
                        remoteProfile: remoteProfile.isEmpty ? nil : remoteProfile, ownershipID: ownershipID))
            }
            let fallbackName =
                switch mode {
                case .gateway: (try? address?.get())?.endpoint.baseURL.host() ?? "Server"
                case .ssh: host.trimmingCharacters(in: .whitespaces)
                }
            let trimmedName = name.trimmingCharacters(in: .whitespaces)
            return ServerConnection(
                id: existingID ?? UUID(), name: trimmedName.isEmpty ? fallbackName : trimmedName, kind: kind,
                requiresUnlock: requiresUnlock, createdAt: createdAt)
        }

        /// The secrets as typed. Imported keys are checked here.
        public func makeSecrets() throws(ConnectionTestFailure) -> ConnectionSecrets {
            switch mode {
            case .gateway:
                var secrets = ConnectionSecrets(
                    password: signInMethod == .password ? password : nil,
                    sessionToken: signInMethod == .token ? token : nil)
                if signInMethod == .browser {
                    switch browserSignInResult {
                    case .tokens(let tokens)?: secrets.nativeTokens = tokens
                    case .cookies(let cookies)?: secrets.webCookies = cookies
                    case nil: break
                    }
                }
                return secrets
            case .ssh:
                switch keySource {
                case .generate:
                    return ConnectionSecrets(sshKey: generatedKey)
                case .importKey:
                    do {
                        return ConnectionSecrets(
                            sshKey: try SSHKeyMaterial.importKey(importText, passphrase: passphrase))
                    } catch {
                        throw SSHConnectionTester.failure(error)
                    }
                }
            }
        }

        /// Runs the connection test. SSH asks the user to trust the host key on first connect.
        ///
        /// The form stays editable while the test runs, so the test keeps the inputs it was started with. Progress and
        /// the result count only while the form still has those inputs and no newer test has started; anything else is
        /// discarded, and an adapted address is remembered only for the address it belongs to.
        public func runTest(with connections: ConnectionsModel) async {
            let connection: ServerConnection
            let secrets: ConnectionSecrets
            do throws(ConnectionTestFailure) {
                connection = try makeConnection()
                secrets = try makeSecrets()
            } catch {
                test = .failed(error)
                return
            }
            // A test from an older form state cannot be completed, so its host-key sheet must not hold this one up.
            resolvePendingTrust(false)
            guard let target = target(for: connection, secrets: secrets) else {
                test = .failed(.invalidForm(missing ?? "Enter a valid server address."))
                return
            }
            let run = testRuns.begin(target)
            test = .running(mode == .ssh ? .connectingSSH : .reachingServer)
            testStage = mode == .ssh ? .connectingSSH : .reachingServer
            do {
                let report = try await connections.tester(for: connection).test(
                    connection, secrets: secrets,
                    progress: { step in
                        Task { @MainActor in self.advance(to: step, run: run) }
                    },
                    confirmHostKey: { fingerprint in
                        await self.askToTrust(fingerprint, run: run)
                    })
                guard isCurrent(run) else {
                    discard(run)
                    return
                }
                if let key = report.acceptedHostKey { pinnedHostKey = key.openSSHKey }
                if case .success(let parsed)? = address {
                    rememberAdapted(report.adaptedEndpoint, for: parsed.endpoint)
                }
                test = .passed(report)
                testRuns.finish(run)
            } catch let failure as ConnectionTestFailure {
                guard isCurrent(run) else {
                    discard(run)
                    return
                }
                test = .failed(failure)
                testRuns.finish(run)
            } catch {
                guard isCurrent(run) else {
                    discard(run)
                    return
                }
                test = .failed(.unreachable("\(error)"))
                testRuns.finish(run)
            }
            if testRuns.current == nil { autoTrustFingerprint = nil }
        }

        /// Clears a test result when the form's target inputs change, so a pass for one address never describes
        /// another. A running test becomes stale and its answer is discarded.
        public func invalidateTest() {
            testRuns.invalidate()
            if test != .idle {
                test = .idle
                testStage = nil
            }
            autoTrustFingerprint = nil
            resolvePendingTrust(false)
        }

        /// The form values a test would use now, or nil while a field is missing.
        private func currentTarget() -> TestTarget? {
            guard let connection = try? makeConnection(), let secrets = try? makeSecrets() else { return nil }
            return target(for: connection, secrets: secrets)
        }

        private func target(for connection: ServerConnection, secrets: ConnectionSecrets) -> TestTarget? {
            switch connection.kind {
            case .gateway(let settings):
                guard case .success(let parsed)? = address else { return nil }
                return TestTarget(
                    gateway: GatewayTarget(typed: parsed.endpoint.baseURL, signIn: settings.signIn),
                    ssh: nil, secrets: secrets)
            case .ssh(let settings):
                return TestTarget(gateway: nil, ssh: settings, secrets: secrets)
            }
        }

        /// True while `run` is the current test and the form still has the inputs it started with.
        private func isCurrent(_ run: TestRun) -> Bool {
            guard let target = currentTarget() else { return false }
            return testRuns.isCurrent(run, target: target)
        }

        /// Drops `run` when the form changed under it. A newer run owns the form state, so its state is left alone.
        private func discard(_ run: TestRun) {
            guard testRuns.isCurrent(run) else { return }
            testRuns.invalidate()
            test = .idle
            testStage = nil
            autoTrustFingerprint = nil
            resolvePendingTrust(false)
        }

        /// The changed-key override: Face ID, then trust the new key and pin it.
        public func trustChangedKey(with connections: ConnectionsModel) async {
            guard case .failed(.hostKeyChanged(_, let actual)) = test else { return }
            guard await connections.services.unlocker.unlock(reason: "Trust the server's new key") else { return }
            autoTrustFingerprint = actual
            pinnedHostKey = nil
            await runTest(with: connections)
        }

        /// The answer from the fingerprint sheet.
        public func answerTrust(_ trusted: Bool) {
            resolvePendingTrust(trusted)
        }

        private func resolvePendingTrust(_ trusted: Bool) {
            pendingTrust?.continuation.resume(returning: trusted)
            pendingTrust = nil
        }

        /// Saves the connection. Returns the saved value, or throws a message for the form.
        @discardableResult
        public func save(to connections: ConnectionsModel) throws -> ServerConnection {
            var connection = try makeConnection()
            if name.trimmingCharacters(in: .whitespaces).isEmpty {
                // A name made from the host gets " 2", " 3"… when another server already uses it.
                connection.name = connections.saved.uniqueName(connection.name, for: connection.id)
            }
            try connections.save(connection, secrets: try makeSecrets())
            return connection
        }

        private func advance(to step: ConnectionTestStep, run: TestRun) {
            guard case .running = test else { return }
            guard isCurrent(run) else {
                discard(run)
                return
            }
            testStage = step
            test = .running(step)
        }

        private func askToTrust(_ fingerprint: HostKeyFingerprint, run: TestRun) async -> Bool {
            guard isCurrent(run) else {
                discard(run)
                return false
            }
            if fingerprint.fingerprint == autoTrustFingerprint { return true }
            // A sheet from an older run must not keep two answers waiting.
            resolvePendingTrust(false)
            return await withCheckedContinuation { continuation in
                pendingTrust = PendingTrust(fingerprint: fingerprint, continuation: continuation)
            }
        }
    }

    extension ConnectionFormModel {
        private struct GatewayTarget: Equatable, Sendable {
            let typed: URL
            let signIn: GatewaySignIn
        }

        /// The form values one test was started with, so a late answer for older inputs can be discarded.
        ///
        /// A gateway target keeps the typed address, not the IP a probe or test may adapt to: discovering an
        /// adaptation while a test runs must not make that test look stale.
        private struct TestTarget: Equatable, Sendable {
            let gateway: GatewayTarget?
            let ssh: SSHSettings?
            let secrets: ConnectionSecrets
        }

        public enum Mode: String, Sendable {
            case gateway
            case ssh
        }

        public enum SignInMethod: String, CaseIterable, Identifiable, Sendable {
            case none = "None"
            case browser = "Browser"
            case password = "Password"
            case token = "Token"
            public var id: String { rawValue }

            init(_ method: SignInOptions.Method) {
                switch method {
                case .browser: self = .browser
                case .password: self = .password
                case .sessionToken: self = .token
                }
            }
        }

        /// Browser sign-in progress (WP-13).
        public enum BrowserState: Equatable, Sendable {
            case idle
            case signingIn
            case signedIn(user: String?)
            case failed(String)
        }

        public enum KeySource: String, CaseIterable, Identifiable, Sendable {
            case generate = "Generate"
            case importKey = "Import"
            public var id: String { rawValue }
        }

        public enum TestState: Equatable, Sendable {
            case idle
            case running(ConnectionTestStep)
            case passed(ConnectionTestReport)
            case failed(ConnectionTestFailure)
        }

        public enum ProbeState: Equatable, Sendable {
            case idle
            case checking
            case found(ServerProbe)
            case failed(ConnectionTestFailure)
        }

        /// A host key waiting for the user's answer in the fingerprint sheet.
        public struct PendingTrust: Identifiable, Sendable {
            public let fingerprint: HostKeyFingerprint
            let continuation: CheckedContinuation<Bool, Never>
            public var id: String { fingerprint.fingerprint }
        }
    }
#endif
