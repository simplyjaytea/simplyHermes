import HermesKit

/// Namespace for the HermesSSH package: SSH session, remote dashboard launch and loopback forwarder (WP-14).
///
/// Entry point: ``SSHTunnel``. It connects with Citadel, starts an `--isolated` `hermes serve` on the remote
/// host (docs/protocol.md section 9), forwards a local loopback port to it and returns an ``SSHTunnelEndpoint``.
public enum HermesSSH {}
