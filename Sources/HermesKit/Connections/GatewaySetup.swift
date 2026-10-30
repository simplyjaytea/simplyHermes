import Foundation

/// The guided gateway setup: the prompt for the Hermes agent on the computer, the checks the setup wizard runs, and what
/// to try when one fails. Plain values only, so the words are tested on Linux (plans/guided-setup).
public enum GatewaySetup {
    /// The checks the wizard shows, in the order they run.
    public enum Check: Int, CaseIterable, Comparable, Sendable {
        /// The address answers.
        case reach
        /// The answer is Hermes, and it is new enough for simplyHermes.
        case hermes
        /// The sign-in works, when the server asks for one.
        case signIn
        /// The live connection opens and answers.
        case live

        public var title: String {
            switch self {
            case .reach: "Reaching the address"
            case .hermes: "Hermes answers"
            case .signIn: "Signing in"
            case .live: "Live connection opens"
            }
        }

        public static func < (lhs: Check, rhs: Check) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// Where one check stands.
    public enum Status: Equatable, Sendable {
        case pending
        case running
        case passed
        case failed(Diagnosis)
    }

    /// What the wizard says about a failed check.
    public struct Diagnosis: Equatable, Sendable {
        /// The check that failed.
        public var check: Check
        /// One sentence on what went wrong.
        public var message: String
        /// What to try, in order. Each item is one short sentence.
        public var fixes: [String]
    }

    /// What the diagnosis needs to know about the address the user typed.
    public struct Address: Equatable, Sendable {
        /// Where the host sits, from the address alone.
        public var host: ConnectionAddress.HostClass
        /// True for `https://`.
        public var usesHTTPS: Bool

        public init(host: ConnectionAddress.HostClass, usesHTTPS: Bool) {
            self.host = host
            self.usesHTTPS = usesHTTPS
        }

        /// The hints for a typed address. Nil when the address is not usable.
        public init?(typed text: String) {
            guard case .success(let parsed) = ConnectionAddress.parse(text) else { return nil }
            host = parsed.hostClass
            usesHTTPS = parsed.endpoint.baseURL.scheme?.lowercased() == "https"
        }
    }

    /// The status of every check, from where the test got to and how it ended.
    /// - Parameters:
    ///   - stage: The last step the test reported. Nil before the first one.
    ///   - failure: The failure that ended the test, if any.
    ///   - passed: True when the test passed.
    ///   - address: The address the user typed, for the hints. Nil leaves the hints out.
    public static func statuses(
        stage: ConnectionTestStep?, failure: ConnectionTestFailure?, passed: Bool, address: Address?
    ) -> [Check: Status] {
        if passed { return table { _ in .passed } }
        if let failure {
            guard let failed = check(for: failure, stage: stage) else { return table { _ in .pending } }
            return table { check in
                if check < failed { return .passed }
                if check == failed {
                    return .failed(diagnosis(for: failure, check: failed, address: address))
                }
                return .pending
            }
        }
        switch stage {
        case .reachingServer:
            return table { check in check == .reach ? .running : .pending }
        case .signingIn:
            return table { check in
                switch check {
                case .reach, .hermes: .passed
                case .signIn: .running
                case .live: .pending
                }
            }
        case .checkingServer, .openingWebSocket:
            return table { check in check == .live ? .running : .passed }
        default:
            return table { _ in .pending }
        }
    }

    /// The message and the things to try for a failed check. `check` is where the failure belongs.
    public static func diagnosis(for failure: ConnectionTestFailure, check: Check, address: Address?) -> Diagnosis {
        let text = words(for: failure, address: address)
        return Diagnosis(check: check, message: text.message, fixes: text.fixes)
    }

    /// A note for an address that is this phone, not the computer. Nil for every other host.
    public static func loopbackNote(for host: ConnectionAddress.HostClass?) -> String? {
        guard host == .loopback else { return nil }
        return "127.0.0.1 is this iPhone, not your computer. Use the computer's address from the setup prompt."
    }

    /// The copy-paste prompt for the Hermes agent on the computer. The agent sets up the service and prints the address
    /// and a `simplyhermes://add` link for the phone. The phone's `<HOST>` placeholder is the computer's Tailscale name.
    public static let prompt = #"""
        Set up this computer as the Hermes server for the simplyHermes app on my iPhone. The phone reaches this
        machine over Tailscale, through HTTPS. Work through the steps in order. Report each step in one line.
        Stop and ask me before any step marked CONFIRM.

        Rules:
        - This prompt is for Linux with systemd. On macOS or Windows, stop and tell me.
        - Change only the Hermes dashboard service, its env file and the Tailscale serve setting for this port.
          Leave sshd and other services alone. Do not install Tailscale.
        - Before you change a file, copy it to NAME.bak-YYYYMMDD.
        - Never run `hermes serve --stop`. It stops every Hermes server on this machine.
        - Never run `tailscale funnel`. It makes the server reachable from the internet.
        - Never bind Hermes to 127.0.0.1 or 0.0.0.0 in this setup. Bind only to the Tailscale address.
        - Port 9119 must answer only on the Tailscale address and on tailscale0. Never open it on a LAN or
          public interface.
        - Run sudo only for the commands marked sudo, and show me each one first.
        - Do not print the password or the secret, except the password in step 8.

        1. Check the machine.
        - Run `tailscale status`. This machine must be online. If Tailscale is missing or logged out, stop and
          tell me.
        - Set TS_IP to the first line of `tailscale ip -4`.
        - Set HOST to the MagicDNS name: the DNSName field of `tailscale status --json`, without its trailing dot.
          It looks like machine.tailnet-name.ts.net.
        - Run `command -v hermes`, `hermes --version` and `hermes serve --help`. The help must list --host and
          --port. If it does not, stop and tell me to update Hermes.
        - Run `tailscale serve --help`. If there is no serve command, stop and tell me to update Tailscale.
        - Note any HERMES_HOME that the current Hermes uses. Keep it.

        2. Check what runs now.
        - Run `ss -ltnp | grep ':9119 '` and `ps -eo pid,user,args | grep 'hermes serve' | grep -v grep`.
        - If a Hermes server is running, say how it started: systemd, tmux, or by hand.
        - CONFIRM: if one runs, show me its address and how it started. Ask me before you stop it. The new
          service needs port 9119 free on the Tailscale address.

        3. Write the sign-in. Run `umask 077` first.
        - File: ~/.config/hermes/dashboard.env. If it already exists, keep its values, add any line below that it
          lacks, and say so.
        - Contents, one variable per line:
          HERMES_DASHBOARD_BASIC_AUTH_USERNAME=hermes
          HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=<20 random letters and digits>
          HERMES_DASHBOARD_BASIC_AUTH_SECRET=<64 random hex characters>
          HERMES_DASHBOARD_PUBLIC_URL=https://<HOST>
        - Make the password and the secret with openssl rand. Set the file mode to 600.
        - The public URL is required. tailscale serve passes the Host header <HOST> through, and Hermes answers
          "Invalid Host header" (HTTP 400) to any name other than its bind address and its public URL.

        4. Write the service.
        - File: /etc/systemd/system/hermes-dashboard.service, with this content, filled in:

          [Unit]
          Description=Hermes dashboard for simplyHermes
          After=network-online.target tailscaled.service
          Wants=network-online.target

          [Service]
          User=<my user>
          WorkingDirectory=/home/<my user>
          Environment=HOME=/home/<my user>
          EnvironmentFile=/home/<my user>/.config/hermes/dashboard.env
          ExecStart=<path from command -v hermes> serve --host <TS_IP> --port 9119
          Restart=on-failure
          RestartSec=5

          [Install]
          WantedBy=multi-user.target

        - Add an Environment=HERMES_HOME line if step 1 found one.
        - CONFIRM: show me the sudo commands and wait for my yes.
        - Run `sudo systemctl daemon-reload`, then `sudo systemctl enable --now hermes-dashboard` (sudo).

        5. Turn on HTTPS in front of the service. CONFIRM: show me the sudo command first.
        - Check the syntax with `tailscale serve --help`. Then run
          `sudo tailscale serve --bg --https=443 http://<TS_IP>:9119`, in the form that help shows.
        - If the output says HTTPS is not enabled, stop. Show me the link it prints. I turn on MagicDNS and
          HTTPS Certificates in the Tailscale admin console (DNS page), then you run this step again.
        - Run `tailscale serve status`. It must show https://<HOST> proxying to http://<TS_IP>:9119.

        6. Firewall. Run `sudo ufw status` (sudo). Only if it says "Status: active", run
          `sudo ufw allow in on tailscale0 to any port 9119 proto tcp` (sudo). Add no other rule.

        7. Check it.
        - `curl -sS --max-time 5 https://<HOST>/api/status` must return JSON with "auth_required": true. If it
          says "Invalid Host header", HERMES_DASHBOARD_PUBLIC_URL is missing from the env file or the service did
          not load it.
        - `curl -sS --max-time 5 http://<TS_IP>:9119/api/status` must return the same kind of JSON.
        - Find the first private IPv4 address that is not on tailscale0 (`ip -4 -br addr`). Call it LAN_IP.
          If there is none, say so and skip this check. Otherwise,
          `curl -sS --max-time 3 http://<LAN_IP>:9119/api/status` must fail. If it answers, stop and tell me.
        - `systemctl is-active hermes-dashboard` must print "active".
        - If any check fails, stop and show me the last 20 lines of `journalctl -u hermes-dashboard --no-pager`
          and the output of `tailscale serve status`.

        8. Print the pairing details, in this order:
        - Address: https://<HOST>
        - Link: simplyhermes://add?url=https%3A%2F%2F<HOST>&name=Home&user=hermes
        - QR code: if `command -v qrencode` finds it, run `qrencode -t ANSIUTF8` with the link in single quotes
          and show the output. If not, say so and skip it.
        - Phone steps: turn on Tailscale on the iPhone. Open Safari at https://<HOST>/api/status. You should see
          JSON. Open simplyHermes, tap Set up on my computer, tap Next, then scan the code or type the address.
          Sign in with user hermes and the password on the last line.
        - Last line, once: Password: <the password>. Add that the same value is also in
          ~/.config/hermes/dashboard.env.

        To undo later: `sudo tailscale serve reset`, which clears every serve setting on this machine. Then run
        `sudo systemctl disable --now hermes-dashboard`, remove the unit file and run `sudo systemctl daemon-reload`.
        Keep the env file.

        Finish with one line: what worked, and what you could not check.
        """#

    /// The first part of a typed check: the words for the failure, by what the failure is.
    private static func words(for failure: ConnectionTestFailure, address: Address?) -> (
        message: String, fixes: [String]
    ) {
        switch failure {
        case .unreachable:
            return reachWords(address)
        case .server where failure.isHostRejected:
            return (
                "Hermes refused this address. It answers only to its own address and its public URL.",
                [
                    "Use the address Hermes listens on: its Tailscale IP and port, such as http://100.x.y.z:9119.",
                    "HTTPS through tailscale serve needs HERMES_DASHBOARD_PUBLIC_URL=<this address> in "
                        + "~/.config/hermes/dashboard.env on the computer. Then restart Hermes.",
                ]
            )
        case .server(let status, _):
            return (
                "The server answered with HTTP \(status), not as Hermes does.",
                [
                    "Run `tailscale serve status` on the computer and check the address.",
                    "Run the setup prompt again.",
                ]
            )
        case .notHermes:
            return (
                "Something answered, but it isn't Hermes.",
                [
                    "Run `tailscale serve status` on the computer. It must point at Hermes's port.",
                    "Run the setup prompt again.",
                ]
            )
        case .serverTooOld(let found):
            return (
                "This Hermes (\(found)) is too old for simplyHermes.",
                ["Update Hermes on the computer with `hermes update`, then test again."]
            )
        case .signInRequired:
            return ("This server needs a password.", ["Enter the user name and password from the setup prompt."])
        case .wrongCredentials:
            return (
                "The user name or password didn't match.",
                [
                    "The password is in ~/.config/hermes/dashboard.env on the computer.",
                    "The user name is hermes, unless you changed it.",
                ]
            )
        case .rateLimited:
            return ("Too many sign-in tries in a short time.", ["Wait a minute, then test again."])
        case .missingSecret:
            return ("Enter the password.", [])
        case .webSocket:
            return (
                "Signed in, but the live connection didn't open.",
                [
                    "If the address is HTTPS, run `tailscale serve status` on the computer.",
                    "A proxy in front of Hermes may block WebSockets.",
                ]
            )
        case .invalidForm, .ssh, .hostKeyRejected, .hostKeyChanged:
            return (failure.message, [])
        }
    }

    /// The words for a failure to reach the address, by where the address sits.
    private static func reachWords(_ address: Address?) -> (message: String, fixes: [String]) {
        switch address?.host {
        case .loopback?:
            return (
                "That address is this iPhone, not your computer.",
                ["Use the address from the setup prompt. It is the computer's Tailscale name."]
            )
        case .tailscale?:
            var fixes = [
                "Turn on Tailscale on this iPhone.",
                "Check that the computer shows as online in the Tailscale app.",
            ]
            if address?.usesHTTPS == true {
                fixes.append("Check that HTTPS Certificates are on in the Tailscale admin console.")
            }
            return ("The computer didn't answer over Tailscale.", fixes)
        case .privateNetwork?:
            return (
                "The computer didn't answer on this network.",
                ["Check that the computer is on the same Wi-Fi.", "In Settings, allow Local Network for simplyHermes."]
            )
        case .publicInternet?, nil:
            return (
                "Nothing answered at that address.",
                [
                    "Check the address in the setup prompt's output.",
                    "Check that the computer is on and Hermes is running.",
                ]
            )
        }
    }

    /// The check a failure belongs to. Nil for failures that are not about the connection, such as a bad form.
    static func check(for failure: ConnectionTestFailure, stage: ConnectionTestStep?) -> Check? {
        switch failure {
        case .notHermes, .serverTooOld:
            return Check.hermes
        case .signInRequired, .wrongCredentials, .rateLimited, .missingSecret:
            return Check.signIn
        case .webSocket:
            return Check.live
        case .unreachable, .server:
            switch stage {
            case .signingIn?, .checkingServer?: return Check.signIn
            case .openingWebSocket?: return Check.live
            default: return Check.reach
            }
        case .invalidForm, .ssh, .hostKeyRejected, .hostKeyChanged:
            return nil
        }
    }

    /// Builds the status of every check from one rule: `status` gives each check's status.
    private static func table(_ status: (Check) -> Status) -> [Check: Status] {
        var result: [Check: Status] = [:]
        for check in Check.allCases { result[check] = status(check) }
        return result
    }
}
