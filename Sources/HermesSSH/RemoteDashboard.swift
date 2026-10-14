import Foundation

/// Remote side of SSH mode (docs/protocol.md section 9): shell scripts to probe for `hermes` and start an
/// `--isolated` dashboard, plus parsers for their output. Pure values, so they are unit tested without SSH.
///
/// Every script runs as `sh -c '<script>'` so it behaves the same whatever the user's login shell is
/// (bash, zsh, fish). Scripts therefore never contain a single quote; values interpolated into them are
/// hex strings or validated paths.
public enum RemoteDashboard {
    /// Default wait for `HERMES_BACKEND_READY` (Desktop uses 120 s; slow hosts need it).
    public static let defaultReadyTimeout: Duration = .seconds(120)

    // MARK: Identifiers

    /// Random lowercase hex of `byteCount` bytes.
    public static func randomHex(byteCount: Int) -> String {
        var generator = SystemRandomNumberGenerator()
        return (0..<byteCount).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max, using: &generator)) }
            .joined()
    }

    /// Per-connection ownership id: 32 lowercase hex chars. Stable for a saved connection.
    public static func makeOwnershipID() -> String { randomHex(byteCount: 16) }
    /// Per-launch nonce: 16 lowercase hex chars.
    public static func makeNonce() -> String { randomHex(byteCount: 8) }
    /// Session token: exactly 64 lowercase hex chars (32 random bytes). The server rejects anything else.
    public static func makeSessionToken() -> String { randomHex(byteCount: 32) }

    static func isLowerHex(_ value: String, count: Int) -> Bool {
        value.count == count && value.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
    }

    /// A custom `hermes` path must be absolute (or `~/…`) and free of shell metacharacters.
    public static func validateHermesPath(_ path: String) throws {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/._-~+@"))
        guard path.hasPrefix("/") || path.hasPrefix("~/"),
            path.unicodeScalars.allSatisfy({ allowed.contains($0) })
        else {
            throw SSHTunnelError.invalidConfiguration(
                "The hermes path must be absolute and use only letters, digits and / . _ - ~ + @")
        }
    }

    // MARK: Scripts

    /// Wraps a script for an exec channel. Precondition: the script contains no single quote.
    static func shellCommand(_ script: String) -> String {
        precondition(!script.contains("'"), "Remote scripts must not contain single quotes")
        return "sh -c '\(script)'"
    }

    /// Finds `hermes` and reports whether it supports SSH token files. Output lines:
    /// `HERMES_PATH=…`, `HERMES_VERSION=…`, `HERMES_SSH_TOKEN_FILE=1|0`, or `HERMES_NOT_FOUND`.
    public static func probeCommand(customPath: String?) throws -> String {
        let lookup: String
        if let customPath {
            // A custom path that is set but missing must not silently fall back to another install.
            try validateHermesPath(customPath)
            let path = customPath.hasPrefix("~/") ? "$HOME/" + customPath.dropFirst(2) : customPath
            lookup = "H=\"\(path)\""
        } else {
            let candidates = [
                "$HOME/.local/bin/hermes", "/usr/local/bin/hermes", "/opt/homebrew/bin/hermes",
                "$HOME/.hermes/bin/hermes",
            ]
            lookup = """
                H=$(command -v hermes 2>/dev/null)
                [ -z "$H" ] && for c in \(candidates.map { "\"\($0)\"" }.joined(separator: " ")); do \
                [ -x "$c" ] && { H="$c"; break; }; done
                [ -z "$H" ] && [ -n "$SHELL" ] && H=$("$SHELL" -lc "command -v hermes" 2>/dev/null | tail -n 1)
                """
        }
        let script = """
            \(lookup)
            if [ -z "$H" ] || [ ! -x "$H" ]; then echo HERMES_NOT_FOUND; exit 0; fi
            echo "HERMES_PATH=$H"
            echo "HERMES_VERSION=$("$H" --version 2>/dev/null | head -n 1)"
            if "$H" serve --help 2>/dev/null | grep -q -- --ssh-session-token-file; then
              echo HERMES_SSH_TOKEN_FILE=1
            else
              echo HERMES_SSH_TOKEN_FILE=0
            fi
            """
        return shellCommand(script)
    }

    /// Stops servers a previous launch of this connection left behind (app killed while backgrounded), writes the
    /// token file, starts `hermes serve --isolated` detached, prints `HERMES_PID=<pid>`, then waits for
    /// `HERMES_BACKEND_READY port=<n>`. Ends with `HERMES_EXITED` (+ log tail) or `HERMES_TIMEOUT` on failure.
    public static func launchCommand(
        hermesPath: String, ownershipID: String, nonce: String, token: String, readyTimeout: Duration
    ) throws -> String {
        try validateHermesPath(hermesPath)
        guard hermesPath.hasPrefix("/") else {
            throw SSHTunnelError.invalidConfiguration("launch needs the absolute path the probe reported")
        }
        guard isLowerHex(ownershipID, count: 32), isLowerHex(nonce, count: 16), isLowerHex(token, count: 64) else {
            throw SSHTunnelError.invalidConfiguration("ownership id, nonce or token has the wrong format")
        }
        let polls = max(1, Int(readyTimeout.components.seconds) * 2)
        let script = """
            umask 077
            D="$HOME/.hermes/desktop-ssh/\(ownershipID)"
            mkdir -p "$D" && chmod 700 "$D" || exit 2
            for p in $(ps -eo pid=,args= 2>/dev/null | grep -- "--ssh-session-token-file $D/" | grep -v grep | awk "{print \\$1}"); do
              kill "$p" 2>/dev/null
            done
            rm -f "$D"/*.log "$D"/*.token
            T="$D/\(nonce).token"
            L="$D/\(nonce).log"
            printf %s \(token) > "$T" && chmod 600 "$T" || exit 2
            : > "$L"
            S=""
            command -v setsid >/dev/null 2>&1 && S=setsid
            HERMES_DESKTOP=1 $S nohup "\(hermesPath)" serve --isolated --host 127.0.0.1 --port 0 \
            --ssh-session-token-file "$T" --ssh-owner-nonce \(nonce) </dev/null >>"$L" 2>&1 &
            P=$!
            echo "HERMES_PID=$P"
            i=0
            while [ $i -lt \(polls) ]; do
              R=$(grep -m 1 -o "HERMES_BACKEND_READY port=[0-9]*" "$L" 2>/dev/null)
              if [ -n "$R" ]; then echo "$R"; exit 0; fi
              if ! kill -0 $P 2>/dev/null; then echo HERMES_EXITED; tail -n 20 "$L"; rm -f "$T"; exit 3; fi
              sleep 0.5
              i=$((i+1))
            done
            echo HERMES_TIMEOUT
            kill $P 2>/dev/null
            rm -f "$T"
            exit 4
            """
        return shellCommand(script)
    }

    /// Stops the dashboard this app started, only if the process still carries our nonce, and removes its log.
    public static func stopCommand(ownershipID: String, nonce: String, pid: Int32) throws -> String {
        guard isLowerHex(ownershipID, count: 32), isLowerHex(nonce, count: 16), pid > 1 else {
            throw SSHTunnelError.invalidConfiguration("ownership id, nonce or pid has the wrong format")
        }
        let script = """
            if ps -o args= -p \(pid) 2>/dev/null | grep -q -- "--ssh-owner-nonce \(nonce)"; then kill \(pid); fi
            rm -f "$HOME/.hermes/desktop-ssh/\(ownershipID)/\(nonce).log" "$HOME/.hermes/desktop-ssh/\(ownershipID)/\(nonce).token"
            exit 0
            """
        return shellCommand(script)
    }

    // MARK: Parsing

    /// Result of ``probeCommand(customPath:)``.
    public struct Probe: Sendable, Equatable {
        public let hermesPath: String
        public let version: String
        public let supportsTokenFile: Bool
    }

    public static func parseProbe(_ output: String) throws -> Probe {
        let lines = output.split(whereSeparator: \.isNewline).map(String.init)
        if lines.contains("HERMES_NOT_FOUND") { throw SSHTunnelError.hermesNotFound }
        func value(_ key: String) -> String? {
            lines.first { $0.hasPrefix(key + "=") }.map { String($0.dropFirst(key.count + 1)) }
        }
        guard let path = value("HERMES_PATH"), let flag = value("HERMES_SSH_TOKEN_FILE") else {
            throw SSHTunnelError.unexpectedOutput(output)
        }
        return Probe(hermesPath: path, version: value("HERMES_VERSION") ?? "", supportsTokenFile: flag == "1")
    }

    /// Parses `HERMES_PID=` from launch output.
    public static func parsePID(_ output: String) -> Int32? {
        output.split(whereSeparator: \.isNewline).lazy
            .compactMap { $0.hasPrefix("HERMES_PID=") ? Int32($0.dropFirst("HERMES_PID=".count)) : nil }
            .first
    }

    /// Parses the outcome of ``launchCommand(hermesPath:ownershipID:nonce:token:readyTimeout:)``.
    /// Returns the remote port, or throws the failure the script reported.
    public static func parseReady(_ output: String) throws -> Int {
        for line in output.split(whereSeparator: \.isNewline) {
            if let range = line.range(of: "HERMES_BACKEND_READY port=") {
                let digits = line[range.upperBound...].prefix { $0.isNumber }
                if let port = Int(digits), (1...65535).contains(port) { return port }
            }
        }
        if let range = output.range(of: "HERMES_EXITED") {
            throw SSHTunnelError.dashboardExited(
                log: output[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if output.contains("HERMES_TIMEOUT") { throw SSHTunnelError.dashboardStartTimedOut }
        throw SSHTunnelError.unexpectedOutput(output)
    }

    /// Served-token adoption: `GET /` embeds `window.__HERMES_SESSION_TOKEN__="<token>"`. Desktop trusts it over
    /// the uploaded token.
    public static func parseServedToken(html: String) -> String? {
        guard let start = html.range(of: "__HERMES_SESSION_TOKEN__") else { return nil }
        let rest = html[start.upperBound...].drop { $0 == " " || $0 == "=" }
        guard let quote = rest.first, quote == "\"" || quote == "'" else { return nil }
        let value = rest.dropFirst().prefix { $0 != quote }
        return value.isEmpty ? nil : String(value)
    }
}
