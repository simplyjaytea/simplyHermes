#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// Settings > GitHub token: the fine-grained token that lets Report a bug file issues from the app.
    public struct GitHubTokenView: View {
        private let tokens: any GitHubTokenStore
        @State private var hasToken: Bool
        @State private var pasted = ""
        @State private var error: String?

        public init(tokens: any GitHubTokenStore = KeychainGitHubTokenStore()) {
            self.tokens = tokens
            _hasToken = State(initialValue: tokens.hasToken)
        }

        public var body: some View {
            Form {
                if hasToken {
                    Section {
                        Label("Token saved", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(HermesColor.statusConnected)
                        Button("Remove token", role: .destructive, action: remove)
                            .accessibilityIdentifier("githubToken.remove")
                    } footer: {
                        Text("Bug reports are filed from the app. Remove the token to send them through github.com.")
                    }
                } else {
                    Section {
                        SecureField("github_pat_…", text: $pasted)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(HermesFont.code)
                            .accessibilityIdentifier("githubToken.field")
                        Button("Save token", action: save)
                            .disabled(GitHubToken.cleaned(pasted) == nil)
                            .accessibilityIdentifier("githubToken.save")
                    } footer: {
                        Text(
                            """
                            Make a fine-grained token with Repository access set to Only simplyHermes and \
                            Issues: Read and write. That token can only open issues there. It stays in this \
                            phone's Keychain and is never synced.
                            """
                        )
                    }
                    Section {
                        Link(destination: GitHubToken.createURL) {
                            Label("Make a token on GitHub", systemImage: "arrow.up.right.square")
                        }
                    }
                }
                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(HermesColor.destructive)
                    }
                }
            }
            .navigationTitle("GitHub token")
            .navigationBarTitleDisplayMode(.inline)
            .hermesFeedback(.approved, trigger: hasToken)
        }

        private func save() {
            guard let token = GitHubToken.cleaned(pasted) else { return }
            do {
                try tokens.setToken(token)
                pasted = ""
                error = nil
                hasToken = true
            } catch {
                self.error = "Couldn't save the token in the Keychain."
            }
        }

        private func remove() {
            do {
                try tokens.removeToken()
                error = nil
                hasToken = false
            } catch {
                self.error = "Couldn't remove the token from the Keychain."
            }
        }
    }

    #Preview("GitHub token, outer", traits: .fixedLayout(width: 466, height: 678)) {
        NavigationStack { GitHubTokenView(tokens: InMemoryGitHubTokenStore()) }
    }

    #Preview("GitHub token saved, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        NavigationStack { GitHubTokenView(tokens: InMemoryGitHubTokenStore(token: "github_pat_x")) }
    }

    #Preview("GitHub token, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        NavigationStack { GitHubTokenView(tokens: InMemoryGitHubTokenStore()) }
    }

    #Preview("GitHub token, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        NavigationStack { GitHubTokenView(tokens: InMemoryGitHubTokenStore()) }
    }
#endif
