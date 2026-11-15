#if canImport(UIKit)
    import HermesKit

    /// The one-step Connect flow for a new gateway: check the sign-in, test, then save (the form's Connect button).
    extension ConnectionFormModel {
        /// What the server offers for signing in. Nil until the probe has answered with it, so the form can show
        /// every method instead.
        public var signInOffer: SignInOptions.Offer? {
            guard case .found(let found) = probe, found.authRequired, found.signInKnown else { return nil }
            return found.signInOptions.offer
        }

        /// True when the server answered that it needs no sign-in.
        public var needsNoSignIn: Bool {
            if case .found(let found) = probe { return !found.authRequired }
            return false
        }

        /// True when the form cannot know the right sign-in method, so it keeps every method reachable: the probe
        /// failed, or the test said the server needs a sign-in the form does not have yet.
        public var needsEveryMethod: Bool {
            if case .failed = probe { return true }
            if case .failed(.signInRequired) = test { return true }
            return false
        }

        /// True once the probe has answered. Connect asks the server first when this is false.
        public var hasProbeAnswer: Bool {
            if case .found = probe { return true }
            return false
        }

        /// True when the server needs a login but names no way to sign in.
        private var offersNoMethod: Bool {
            guard case .found(let found) = probe, found.authRequired, found.signInKnown else { return false }
            return found.signInOptions.offer.offersNothing
        }

        /// What Connect still needs, in words for the form, or nil when it can run. Gateways say how to sign in.
        public var connectMissing: String? {
            guard mode == .gateway else { return missing }
            if offersNoMethod && token.isEmpty {
                return "This server requires sign-in but offers no sign-in method. "
                    + "On the server, set a username and password or run `hermes dashboard register`."
            }
            if let missing {
                if signInMethod == .browser, case .success? = address {
                    return "Sign in with one of the buttons above, or enter a user name and password."
                }
                return missing
            }
            if signInMethod == .password && password.isEmpty { return "Enter the password." }
            return nil
        }

        /// Signs in with the browser for `provider` (nil lets the server choose). True when it succeeded.
        public func browserSignIn(provider: String?, with services: ConnectionServices) async -> Bool {
            browserProvider = provider
            return await signInWithBrowser(with: services)
        }

        /// One press: reads the server's sign-in needs when the probe has not answered, runs the test and, when it
        /// passes, saves. Returns the saved connection, or nil when something is missing or the test failed (the
        /// form shows which step). Throws when the save is refused. Never signs in more than once: the test makes
        /// the one login, and a failure leaves the form for the user to fix and press again.
        public func connect(
            with connections: ConnectionsModel, localNetworkExplained: Bool
        ) async throws -> ServerConnection? {
            guard !isTesting else { return nil }
            if !hasProbeAnswer {
                await probeAddress(with: connections.services, localNetworkExplained: localNetworkExplained)
            }
            guard connectMissing == nil, !showsLocalNetworkExplainer else { return nil }
            await runTest(with: connections)
            guard case .passed = test else { return nil }
            return try save(to: connections)
        }
    }
#endif
