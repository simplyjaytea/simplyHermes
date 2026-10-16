#if canImport(UIKit)
    import HermesKit
    import SwiftUI
    import UIKit

    /// GitHub sign-in for Report a bug: the device flow, and the token it saves.
    @MainActor
    @Observable
    public final class GitHubSignInModel {
        public enum Phase: Equatable {
            case signedOut
            case starting
            /// Showing the code; the app polls until the user approves it on github.com.
            case waiting(GitHubDeviceCode)
            case signedIn
            case failed(String)
        }

        public private(set) var phase: Phase

        @ObservationIgnored private let flow: GitHubDeviceFlow
        @ObservationIgnored private let tokens: any GitHubTokenStore
        @ObservationIgnored private var task: Task<Void, Never>?

        public init(
            flow: GitHubDeviceFlow = GitHubDeviceFlow(transport: URLSessionHTTPTransport()),
            tokens: any GitHubTokenStore = KeychainGitHubTokenStore()
        ) {
            self.flow = flow
            self.tokens = tokens
            phase = tokens.hasToken ? .signedIn : .signedOut
        }

        /// False when this build has no GitHub App client ID.
        public var isAvailable: Bool { flow.isConfigured }

        public func signIn() {
            task?.cancel()
            phase = .starting
            task = Task { [flow, tokens] in
                do {
                    let code = try await flow.start()
                    phase = .waiting(code)
                    let token = try await flow.token(for: code)
                    try tokens.setToken(token)
                    phase = .signedIn
                } catch is CancellationError {
                    phase = .signedOut
                } catch let error as GitHubSignInError {
                    phase = .failed(error.message)
                } catch {
                    phase = Task.isCancelled ? .signedOut : .failed("Couldn't reach GitHub. Check your connection.")
                }
            }
        }

        public func cancel() {
            task?.cancel()
            task = nil
            phase = .signedOut
        }

        public func signOut() {
            cancel()
            try? tokens.removeToken()
        }
    }

    /// Settings > GitHub account.
    public struct GitHubAccountView: View {
        @State private var model: GitHubSignInModel
        @Environment(\.openURL) private var openURL

        public init(model: GitHubSignInModel = GitHubSignInModel()) {
            _model = State(initialValue: model)
        }

        public var body: some View {
            Form {
                if !model.isAvailable {
                    Section {
                        Text("GitHub sign-in isn't set up in this build yet.")
                    } footer: {
                        Text("Report a bug still works: Send opens the report on github.com.")
                    }
                } else {
                    content
                }
            }
            .navigationTitle("GitHub account")
            .navigationBarTitleDisplayMode(.inline)
            .hermesFeedback(.approved, trigger: model.phase == .signedIn)
            .onDisappear {
                if case .waiting = model.phase { model.cancel() }
            }
        }

        @ViewBuilder
        private var content: some View {
            switch model.phase {
            case .signedOut, .starting:
                Section {
                    Button("Sign in with GitHub", action: model.signIn)
                        .buttonStyle(HermesButtonStyle(.primary))
                        .disabled(model.phase == .starting)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                        .accessibilityIdentifier("github.signIn")
                } footer: {
                    Text(
                        """
                        Lets Report a bug file issues as you. The app can only open and edit issues in \
                        simplyHermes. The sign-in stays in this phone's Keychain and is never synced.
                        """
                    )
                }
            case .waiting(let code):
                Section {
                    VStack(spacing: 12) {
                        Text("Enter this code on GitHub")
                            .font(HermesFont.subheadline)
                            .foregroundStyle(HermesColor.secondaryText)
                        Text(code.userCode)
                            .font(.system(.largeTitle, design: .monospaced).bold())
                            .textSelection(.enabled)
                            .accessibilityIdentifier("github.userCode")
                        Button("Copy code and open GitHub") {
                            UIPasteboard.general.string = code.userCode
                            openURL(code.verificationURL)
                        }
                        .buttonStyle(HermesButtonStyle(.primary))
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Waiting for you to approve…")
                                .font(HermesFont.footnote)
                                .foregroundStyle(HermesColor.secondaryText)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                Section {
                    Button("Cancel", role: .cancel, action: model.cancel)
                }
            case .signedIn:
                Section {
                    Label("Signed in to GitHub", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(HermesColor.statusConnected)
                    Button("Sign out", role: .destructive, action: model.signOut)
                        .accessibilityIdentifier("github.signOut")
                } footer: {
                    Text("Report a bug files issues from the app.")
                }
            case .failed(let message):
                Section {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(HermesColor.destructive)
                    Button("Try again", action: model.signIn)
                }
            }
        }
    }

    #Preview("GitHub account, outer", traits: .fixedLayout(width: 466, height: 678)) {
        NavigationStack {
            GitHubAccountView(
                model: GitHubSignInModel(
                    flow: GitHubDeviceFlow(transport: URLSessionHTTPTransport(), clientID: "preview"),
                    tokens: InMemoryGitHubTokenStore()))
        }
    }

    #Preview("GitHub account, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        NavigationStack {
            GitHubAccountView(
                model: GitHubSignInModel(
                    flow: GitHubDeviceFlow(transport: URLSessionHTTPTransport(), clientID: "preview"),
                    tokens: InMemoryGitHubTokenStore(token: "ghu_preview")))
        }
    }

    #Preview("GitHub account, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        NavigationStack { GitHubAccountView(model: GitHubSignInModel(tokens: InMemoryGitHubTokenStore())) }
    }

    #Preview("GitHub account, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        NavigationStack { GitHubAccountView(model: GitHubSignInModel(tokens: InMemoryGitHubTokenStore())) }
    }
#endif
