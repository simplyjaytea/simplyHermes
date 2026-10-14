/// Failures surfaced by ``SSHTunnel``. Each case maps to one user-facing state in the connection UI.
public enum SSHTunnelError: Error, Equatable, Sendable {
    /// The server's host key differs from the pinned one. Never retried automatically.
    case hostKeyMismatch(expected: String, actual: String)
    /// The user declined the host key on first connect.
    case hostKeyRejected(fingerprint: String)
    /// No `hermes` executable found on the remote host (custom path, `PATH`, login shell, common dirs).
    case hermesNotFound
    /// The remote Hermes predates `--ssh-session-token-file`. UI: "Update Hermes on the server".
    case hermesTooOld(version: String)
    /// `hermes serve` exited before printing `HERMES_BACKEND_READY`. `log` is the tail of its output.
    case dashboardExited(log: String)
    /// No `HERMES_BACKEND_READY` line within the ready timeout.
    case dashboardStartTimedOut
    /// The remote command produced output this client cannot parse.
    case unexpectedOutput(String)
    /// The private key could not be read (format, passphrase or unsupported type).
    case invalidPrivateKey(String)
    /// A configuration value is unsafe to pass to the remote shell.
    case invalidConfiguration(String)
    /// The tunnel is not running.
    case notConnected
}
