import Foundation

/// The code the user types on github.com to approve the sign-in.
public struct GitHubDeviceCode: Sendable, Equatable {
    /// Secret the app polls with. Never shown.
    public var deviceCode: String
    /// Short code the user types, such as `WDJB-MJHT`.
    public var userCode: String
    /// Where the user types it, `https://github.com/login/device`.
    public var verificationURL: URL
    /// Seconds until the code stops working.
    public var expiresIn: Int
    /// Seconds to wait between polls.
    public var interval: Int

    /// Creates a code.
    public init(deviceCode: String, userCode: String, verificationURL: URL, expiresIn: Int, interval: Int) {
        self.deviceCode = deviceCode
        self.userCode = userCode
        self.verificationURL = verificationURL
        self.expiresIn = expiresIn
        self.interval = interval
    }
}

/// Why GitHub sign-in stopped.
public enum GitHubSignInError: Error, Sendable, Equatable {
    /// This build has no GitHub App client ID.
    case notConfigured
    /// The code ran out before the user approved it.
    case expired
    /// The user tapped Cancel on github.com.
    case denied
    /// Anything else, with GitHub's error code or the HTTP status.
    case failed(String)

    /// One sentence for the screen.
    public var message: String {
        switch self {
        case .notConfigured: "GitHub sign-in isn't set up in this build yet."
        case .expired: "The code expired. Start again to get a new one."
        case .denied: "Sign-in was cancelled on GitHub."
        case .failed(let detail): "GitHub sign-in failed (\(detail))."
        }
    }
}

/// Signs in to GitHub with the device flow: the app shows a code, the user approves it on github.com, and the app
/// receives a user token. No secret ships in the app; the GitHub App's client ID is public.
///
/// The token can only do what the simplyHermes GitHub App allows (Issues: Read and write) on the repositories it is
/// installed on, and only what the user could do anyway.
public struct GitHubDeviceFlow: Sendable {
    /// The simplyHermes GitHub App's client ID. Empty until the app is registered; sign-in then reports
    /// ``GitHubSignInError/notConfigured`` and Report a bug sends through github.com instead.
    public static let simplyHermesClientID = ""

    private static let deviceCodeURL = URL(string: "https://github.com/login/device/code")!
    private static let tokenURL = URL(string: "https://github.com/login/oauth/access_token")!

    private let transport: any HTTPTransport
    private let clientID: String
    private let sleep: @Sendable (Int) async throws -> Void

    /// Creates a flow. `sleep` waits the given seconds between polls; tests pass one that returns at once.
    public init(
        transport: any HTTPTransport,
        clientID: String = GitHubDeviceFlow.simplyHermesClientID,
        sleep: @escaping @Sendable (Int) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }
    ) {
        self.transport = transport
        self.clientID = clientID
        self.sleep = sleep
    }

    /// True when this build can sign in.
    public var isConfigured: Bool { !clientID.isEmpty }

    /// Asks GitHub for a code to show the user.
    public func start() async throws -> GitHubDeviceCode {
        guard isConfigured else { throw GitHubSignInError.notConfigured }
        let body = try await post(Self.deviceCodeURL, ["client_id": clientID])
        guard let deviceCode = body["device_code"] as? String, let userCode = body["user_code"] as? String,
            let uri = body["verification_uri"] as? String, let url = URL(string: uri)
        else { throw GitHubSignInError.failed(body["error"] as? String ?? "no code") }
        return GitHubDeviceCode(
            deviceCode: deviceCode, userCode: userCode, verificationURL: url,
            expiresIn: body["expires_in"] as? Int ?? 900, interval: body["interval"] as? Int ?? 5)
    }

    /// Waits for the user to approve `code` and returns the token. Cancel the task to stop waiting.
    public func token(for code: GitHubDeviceCode) async throws -> String {
        var interval = max(code.interval, 1)
        var waited = 0
        while waited < code.expiresIn {
            try await sleep(interval)
            waited += interval
            let body = try await post(
                Self.tokenURL,
                [
                    "client_id": clientID, "device_code": code.deviceCode,
                    "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                ])
            if let token = body["access_token"] as? String, !token.isEmpty { return token }
            switch body["error"] as? String {
            case "authorization_pending": continue
            // GitHub asks for a longer wait and says how long; otherwise add 5 seconds as the spec says.
            case "slow_down": interval = body["interval"] as? Int ?? interval + 5
            case "expired_token": throw GitHubSignInError.expired
            case "access_denied": throw GitHubSignInError.denied
            case let error?: throw GitHubSignInError.failed(error)
            case nil: throw GitHubSignInError.failed("no token")
            }
        }
        throw GitHubSignInError.expired
    }

    /// GitHub answers these endpoints with 200 and an `error` field, so the body decides, not the status.
    private func post(_ url: URL, _ fields: [String: String]) async throws -> [String: Any] {
        // Form encoding: everything but unreserved characters is escaped, so ":" and "+" arrive intact.
        let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let form = fields.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? "")" }
            .joined(separator: "&")
        let request = HTTPRequest(
            method: "POST", url: url,
            headers: ["Accept": "application/json", "Content-Type": "application/x-www-form-urlencoded"],
            body: Data(form.utf8))
        let response = try await transport.send(request)
        guard let object = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any] else {
            throw GitHubSignInError.failed("HTTP \(response.status)")
        }
        return object
    }
}
