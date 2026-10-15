#if canImport(UIKit)
    import AuthenticationServices
    import Foundation
    import HermesKit
    import UIKit
    import WebKit

    /// What a browser sign-in produced.
    public enum BrowserSignInResult: Sendable, Equatable {
        /// Native sign-in (RFC 8252): bearer and refresh tokens.
        case tokens(NativeTokens)
        /// Web view fallback on a server without native sign-in: its session cookies.
        case cookies([StoredCookie])

        /// The signed-in user, when known.
        public var userID: String? {
            if case .tokens(let tokens) = self { return tokens.userID }
            return nil
        }
    }

    /// Runs a browser sign-in. The app uses ``SystemBrowserSignIn``; tests and previews swap it.
    public protocol BrowserSigningIn: Sendable {
        /// Signs in to `endpoint`. `provider` nil lets the server pick its only provider or show a chooser.
        @MainActor
        func signIn(
            endpoint: HermesEndpoint, options: SignInOptions?, provider: String?
        ) async throws -> BrowserSignInResult
    }

    /// Browser sign-in in the order of plan 2.3:
    /// 1. Native PKCE in the system sign-in sheet (`ASWebAuthenticationSession`), with a loopback listener catching the
    ///    redirect.
    /// 2. If the sheet or the listener cannot start, the same native flow in an in-app web view, which catches the
    ///    redirect itself.
    /// 3. On a server without native sign-in, the in-app web view keeps the session cookies.
    public struct SystemBrowserSignIn: BrowserSigningIn {
        public init() {}

        @MainActor
        public func signIn(
            endpoint: HermesEndpoint, options: SignInOptions?, provider: String?
        ) async throws -> BrowserSignInResult {
            let exchange = RESTClient(endpoint: endpoint, transport: URLSessionHTTPTransport())
            guard options?.supportsNativePKCE ?? true else {
                let login = endpoint.url(
                    forPath: "/auth/login?provider=" + (provider ?? options?.browserProviders.first?.name ?? ""))
                let cookies = try await WebSignInController.run(.cookies(start: login, endpoint: endpoint))
                return .cookies(cookies)
            }
            if let redirect = try await sheetSignIn(endpoint: endpoint, provider: provider, exchange: exchange) {
                return redirect
            }
            let request = NativeSignInRequest(endpoint: endpoint, provider: provider, port: 1)
            let url = try await WebSignInController.runNative(request)
            return .tokens(
                try await exchange.nativeToken(code: try request.code(from: url), verifier: request.pkce.verifier))
        }

        /// The system sheet with a loopback listener. Nil when either could not start (use the web view).
        @MainActor
        private func sheetSignIn(
            endpoint: HermesEndpoint, provider: String?, exchange: RESTClient
        ) async throws -> BrowserSignInResult? {
            guard let receiver = try? LoopbackRedirectReceiver(), let port = try? await receiver.start() else {
                return nil
            }
            let request = NativeSignInRequest(endpoint: endpoint, provider: provider, port: port)
            let anchor = SheetAnchor()
            let session = ASWebAuthenticationSession(
                url: request.authorizeURL, callback: .customScheme("simplyhermes-auth")
            ) { _, _ in
                // Called when the user closes the sheet, or after cancel() below. The listener ends either way.
                receiver.cancel()
            }
            session.presentationContextProvider = anchor
            session.prefersEphemeralWebBrowserSession = true
            guard session.start() else {
                receiver.cancel()
                return nil
            }
            defer { session.cancel() }
            let redirect = try await withTaskCancellationHandler {
                try await receiver.redirect()
            } onCancel: {
                receiver.cancel()
            }
            let code = try request.code(from: redirect)
            return .tokens(try await exchange.nativeToken(code: code, verifier: request.pkce.verifier))
        }
    }

    /// Presents the sign-in sheet over the key window.
    private final class SheetAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            MainActor.assumeIsolated { UIApplication.shared.keyWindowForSignIn ?? ASPresentationAnchor() }
        }
    }

    extension UIApplication {
        @MainActor
        fileprivate var keyWindowForSignIn: UIWindow? {
            connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        }

        @MainActor
        fileprivate var topViewController: UIViewController? {
            var top = keyWindowForSignIn?.rootViewController
            while let presented = top?.presentedViewController { top = presented }
            return top
        }
    }

    /// The in-app web view fallback (plan 2.3 step 1 of the fallbacks): a sheet with a `WKWebView` and Cancel.
    @MainActor
    final class WebSignInController: UIViewController, WKNavigationDelegate {
        enum Mode {
            /// Native PKCE: stop at the loopback redirect instead of loading it.
            case native(NativeSignInRequest)
            /// Cookie sign-in: stop when the browser lands back on the gateway outside the login pages.
            case cookies(start: URL, endpoint: HermesEndpoint)
        }

        private let mode: Mode
        private var continuation: CheckedContinuation<WebOutcome, any Error>?
        private let webView: WKWebView

        private enum WebOutcome {
            case redirect(URL)
            case cookies([StoredCookie])
        }

        private init(mode: Mode) {
            self.mode = mode
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            webView = WKWebView(frame: .zero, configuration: configuration)
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        static func runNative(_ request: NativeSignInRequest) async throws -> URL {
            guard case .redirect(let url) = try await present(.native(request)) else {
                throw NativeSignInError.missingCode
            }
            return url
        }

        static func run(_ mode: Mode) async throws -> [StoredCookie] {
            guard case .cookies(let cookies) = try await present(mode) else { throw NativeSignInError.missingCode }
            return cookies
        }

        private static func present(_ mode: Mode) async throws -> WebOutcome {
            guard let host = UIApplication.shared.topViewController else { throw NativeSignInError.cancelled }
            let controller = WebSignInController(mode: mode)
            let navigation = UINavigationController(rootViewController: controller)
            return try await withCheckedThrowingContinuation { continuation in
                controller.continuation = continuation
                host.present(navigation, animated: true)
            }
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            title = "Sign in"
            navigationItem.leftBarButtonItem = UIBarButtonItem(
                systemItem: .cancel,
                primaryAction: UIAction { [weak self] _ in self?.finish(.failure(NativeSignInError.cancelled)) })
            webView.navigationDelegate = self
            webView.accessibilityIdentifier = "signIn.webView"
            view = webView
            switch mode {
            case .native(let request): webView.load(URLRequest(url: request.authorizeURL))
            case .cookies(let start, _): webView.load(URLRequest(url: start))
            }
        }

        func webView(
            _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .allow }
            switch mode {
            case .native(let request):
                guard request.isRedirect(url) else { return .allow }
                finish(.success(.redirect(url)))
                return .cancel
            case .cookies(_, let endpoint):
                guard Self.isBackOnGateway(url, endpoint: endpoint) else { return .allow }
                let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
                let host = endpoint.baseURL.host ?? ""
                let matching = cookies.filter { host == $0.domain || host.hasSuffix($0.domain) }
                finish(.success(.cookies(matching.map(StoredCookie.init))))
                return .cancel
            }
        }

        /// True for a gateway page that is not part of signing in: the login finished.
        static func isBackOnGateway(_ url: URL, endpoint: HermesEndpoint) -> Bool {
            let base = endpoint.baseURL
            guard url.host == base.host, url.port == base.port else { return false }
            let prefix = base.path.hasSuffix("/") ? String(base.path.dropLast()) : base.path
            let path = url.path.hasPrefix(prefix) ? String(url.path.dropFirst(prefix.count)) : url.path
            return !(path.hasPrefix("/login") || path.hasPrefix("/auth/"))
        }

        private func finish(_ outcome: Result<WebOutcome, any Error>) {
            guard let continuation else { return }
            self.continuation = nil
            dismiss(animated: true)
            continuation.resume(with: outcome)
        }
    }
#endif
