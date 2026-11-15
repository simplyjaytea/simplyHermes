#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// The sign-in controls for one gateway, driven by what the server offers: "No sign-in needed", one "Continue
    /// with" button for each browser provider (including providers the app does not know), the user name and password
    /// fields for a password provider, and More options with the session token. Before the probe answers, or when it
    /// fails, every method sits under More options so the user is never locked out. The gateway form and the setup
    /// wizard both use it.
    struct SignInMethodSection: View {
        @Environment(\.hermesPalette) private var palette
        @Bindable var form: ConnectionFormModel
        let connections: ConnectionsModel
        /// The prefix of the accessibility identifiers: `connection` in the form, `setup` in the wizard.
        let idPrefix: String
        /// True in the wizard, where the fields sit on a card and not in a list row.
        let bordered: Bool
        /// Runs after a browser sign-in succeeds, so a new server can go straight on to Connect.
        let onSignedIn: (() -> Void)?
        @State private var moreOpen: Bool

        init(
            form: ConnectionFormModel, connections: ConnectionsModel, idPrefix: String = "connection",
            bordered: Bool = false, onSignedIn: (() -> Void)? = nil
        ) {
            self.form = form
            self.connections = connections
            self.idPrefix = idPrefix
            self.bordered = bordered
            self.onSignedIn = onSignedIn
            // An edited connection shows its current sign-in at once, even before the probe answers.
            _moreOpen = State(initialValue: form.existingID != nil)
        }

        var body: some View {
            Group {
                primary
                if !form.needsNoSignIn {
                    DisclosureGroup("More options", isExpanded: $moreOpen) { moreOptions }
                        .onChange(of: form.needsEveryMethod) { _, needed in
                            if needed { moreOpen = true }
                        }
                }
            }
        }

        // MARK: Sections

        @ViewBuilder
        private var primary: some View {
            if form.needsNoSignIn {
                Label("No sign-in needed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(palette.statusConnected)
                    .accessibilityIdentifier("\(idPrefix).noSignIn")
            } else if let offer = form.signInOffer {
                offered(offer)
            } else {
                switch form.probe {
                case .checking:
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Checking the server…").foregroundStyle(palette.secondaryText)
                    }
                case .failed:
                    Text("The server could not be checked. Every sign-in method is under More options.")
                        .font(HermesFont.footnote)
                        .foregroundStyle(palette.secondaryText)
                case .idle, .found:
                    Text("The sign-in options appear here once the address is checked.")
                        .font(HermesFont.footnote)
                        .foregroundStyle(palette.secondaryText)
                }
            }
        }

        @ViewBuilder
        private func offered(_ offer: SignInOptions.Offer) -> some View {
            ForEach(Array(offer.browserProviders.enumerated()), id: \.offset) { index, provider in
                let base = "\(idPrefix).browserSignIn"
                browserButton(
                    "Continue with \(provider.displayName ?? provider.name)", provider: provider.name,
                    identifier: index == 0 ? base : "\(base).\(provider.name)")
            }
            if offer.genericBrowser {
                browserButton("Sign in with the browser", provider: nil, identifier: "\(idPrefix).browserSignIn")
            }
            if offer.passwordProvider != nil { passwordFields }
            browserFeedback
            if offer.offersNothing {
                Label(
                    "This server requires sign-in but offers no sign-in method. "
                        + "On the server, set a username and password or run `hermes dashboard register`.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(palette.statusWarning)
                .accessibilityIdentifier("\(idPrefix).noSignInMethod")
            }
        }

        /// Under More options: the session token, and before the server has answered, every other method too.
        @ViewBuilder
        private var moreOptions: some View {
            if form.signInOffer == nil {
                browserButton("Sign in with the browser", provider: nil, identifier: "\(idPrefix).browserSignIn")
                passwordFields
                browserFeedback
            }
            SecureField("Session token", text: $form.token)
                .font(HermesFont.code)
                .modifier(SignInFieldChrome(bordered: bordered))
                .accessibilityIdentifier("\(idPrefix).token")
            Text("Stored in the Keychain on this iPhone only.")
                .font(HermesFont.footnote)
                .foregroundStyle(palette.secondaryText)
        }

        @ViewBuilder
        private var passwordFields: some View {
            TextField("User name", text: $form.username)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .modifier(SignInFieldChrome(bordered: bordered))
                .accessibilityIdentifier("\(idPrefix).username")
            SecureField("Password", text: $form.password)
                .textContentType(.password)
                .modifier(SignInFieldChrome(bordered: bordered))
                .accessibilityIdentifier("\(idPrefix).password")
            Toggle("Remember password", isOn: $form.remembersPassword)
                .accessibilityIdentifier("\(idPrefix).rememberPassword")
            Text(
                form.remembersPassword
                    ? "Kept in the Keychain on this iPhone only, so the app can sign in again by itself."
                    : "Not stored. The app asks again when the server signs you out."
            )
            .font(HermesFont.footnote)
            .foregroundStyle(palette.secondaryText)
            Text("Tip: set HERMES_DASHBOARD_BASIC_AUTH_SECRET on the server, or every restart signs you out.")
                .font(HermesFont.footnote)
                .foregroundStyle(palette.secondaryText)
                .accessibilityIdentifier("\(idPrefix).basicAuthTip")
        }

        // MARK: Browser sign-in

        private func browserButton(_ title: String, provider: String?, identifier: String) -> some View {
            Button {
                Task {
                    if await form.browserSignIn(provider: provider, with: connections.services) { onSignedIn?() }
                }
            } label: {
                HStack {
                    Text(title)
                    if form.browserState == .signingIn && form.browserProvider == provider { ProgressView() }
                }
            }
            .buttonStyle(HermesButtonStyle(.tinted))
            .disabled(form.browserState == .signingIn)
            .accessibilityIdentifier(identifier)
        }

        @ViewBuilder
        private var browserFeedback: some View {
            switch form.browserState {
            case .idle, .signingIn:
                EmptyView()
            case .signedIn(let user):
                Label(user.map { "Signed in as \($0)" } ?? "Signed in", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(palette.statusConnected)
                    .accessibilityIdentifier("\(idPrefix).browserSignedIn")
            case .failed(let message):
                Label(message, systemImage: "xmark.octagon.fill")
                    .foregroundStyle(palette.errorText)
            }
        }
    }

    /// Rounded borders in the wizard, where the fields sit on a card. Form rows keep their own look.
    private struct SignInFieldChrome: ViewModifier {
        let bordered: Bool

        @ViewBuilder
        func body(content: Content) -> some View {
            if bordered {
                content.textFieldStyle(.roundedBorder)
            } else {
                content
            }
        }
    }
#endif
