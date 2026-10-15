import Foundation

/// Turns what the user typed into a gateway ``HermesEndpoint`` and applies the plain-HTTP rule (plan Q14):
/// `http://` is allowed for local, private and Tailscale addresses, with a warning, and refused everywhere else.
public enum ConnectionAddress {
    /// Where a host sits, as far as the app can tell from its name or IP address.
    public enum HostClass: String, Sendable, Equatable {
        /// `localhost`, `127.0.0.0/8`, `::1`.
        case loopback
        /// RFC 1918 and link-local IPv4, unique-local and link-local IPv6, `.local`, `.home.arpa`, single-label names.
        case privateNetwork
        /// Tailscale: `100.64.0.0/10`, `fd7a:115c:a1e0::/48`, `*.ts.net`.
        case tailscale
        /// Anything else.
        case publicInternet
    }

    /// A warning shown under the URL field. The connection can still be saved.
    public enum Warning: Sendable, Equatable {
        /// Plain HTTP on a local or private network: anyone on the network can read the traffic.
        case unencryptedLocal
        /// Plain HTTP over Tailscale: the tunnel encrypts it, but the server sees no TLS.
        case unencryptedTailscale
    }

    /// Why the input cannot be used.
    public enum Problem: Error, Sendable, Equatable {
        /// Nothing typed.
        case empty
        /// Not a URL the app understands.
        case invalid
        /// A scheme other than `http` or `https`.
        case unsupportedScheme(String)
        /// Plain HTTP to a public host. Use HTTPS, Tailscale or SSH.
        case httpNotAllowed(host: String)
    }

    /// A usable address.
    public struct Parsed: Sendable, Equatable {
        /// The endpoint to save.
        public var endpoint: HermesEndpoint
        /// Where the host sits.
        public var hostClass: HostClass
        /// A warning to show, if any.
        public var warning: Warning?
        /// True when the app needs the Local Network permission to reach this host.
        public var needsLocalNetwork: Bool { hostClass == .privateNetwork }
    }

    /// Parses `input`. Without a scheme, local, private and Tailscale hosts get `http://` and others `https://`.
    /// Spaces around the input and a trailing slash are dropped.
    public static func parse(_ input: String) -> Result<Parsed, Problem> {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .failure(.empty) }
        let schemeEnd = text.range(of: "://")?.lowerBound
        let hasAuthority = schemeEnd.map { text[$0...].dropFirst(3).contains { $0 != "/" } } ?? true
        guard hasAuthority else { return .failure(.invalid) }
        while text.hasSuffix("/") { text.removeLast() }

        if let schemeEnd {
            let scheme = text[..<schemeEnd].lowercased()
            guard scheme == "http" || scheme == "https" else { return .failure(.unsupportedScheme(scheme)) }
        } else {
            guard let host = hostPart(ofSchemeless: text) else { return .failure(.invalid) }
            text = (classify(host: host) == .publicInternet ? "https://" : "http://") + text
        }

        guard let components = URLComponents(string: text), let host = components.host, !host.isEmpty,
            !host.contains(" "), let endpoint = HermesEndpoint(string: text)
        else { return .failure(.invalid) }

        let hostClass = classify(host: host)
        let isHTTP = components.scheme?.lowercased() == "http"
        guard isHTTP else { return .success(Parsed(endpoint: endpoint, hostClass: hostClass, warning: nil)) }
        switch hostClass {
        case .loopback:
            return .success(Parsed(endpoint: endpoint, hostClass: hostClass, warning: nil))
        case .privateNetwork:
            return .success(Parsed(endpoint: endpoint, hostClass: hostClass, warning: .unencryptedLocal))
        case .tailscale:
            return .success(Parsed(endpoint: endpoint, hostClass: hostClass, warning: .unencryptedTailscale))
        case .publicInternet:
            return .failure(.httpNotAllowed(host: host))
        }
    }

    /// Classifies a host name or IP address literal (IPv6 with or without brackets).
    public static func classify(host rawHost: String) -> HostClass {
        var host = rawHost.lowercased()
        if host.hasPrefix("[") && host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        if host.hasSuffix(".") { host.removeLast() }

        if let octets = ipv4Octets(host) { return classify(ipv4: octets) }
        if host.contains(":") { return classify(ipv6: host) }

        if host == "localhost" || host.hasSuffix(".localhost") { return .loopback }
        if host.hasSuffix(".ts.net") { return .tailscale }
        let privateSuffixes = [".local", ".home.arpa", ".lan", ".internal"]
        if !host.contains(".") || privateSuffixes.contains(where: host.hasSuffix) { return .privateNetwork }
        return .publicInternet
    }

    // MARK: - Helpers

    /// The host of `host[:port][/path]`, or nil when it is not one.
    private static func hostPart(ofSchemeless text: String) -> String? {
        let authority = text.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first.map(
            String.init)
        guard let authority, !authority.isEmpty, !authority.contains("@") else { return nil }
        if authority.hasPrefix("[") {
            guard let close = authority.firstIndex(of: "]") else { return nil }
            return String(authority[...close])
        }
        return authority.split(separator: ":", maxSplits: 1).first.map(String.init)
    }

    private static func ipv4Octets(_ host: String) -> [Int]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        let octets = parts.compactMap { part -> Int? in
            guard !part.isEmpty, part.count <= 3, part.allSatisfy(\.isASCII), let value = Int(part), value <= 255
            else { return nil }
            return value
        }
        return octets.count == 4 ? octets : nil
    }

    private static func classify(ipv4 octets: [Int]) -> HostClass {
        switch (octets[0], octets[1]) {
        case (127, _): return .loopback
        case (10, _), (192, 168), (169, 254): return .privateNetwork
        case (172, 16...31): return .privateNetwork
        case (100, 64...127): return .tailscale
        default: return .publicInternet
        }
    }

    private static func classify(ipv6 host: String) -> HostClass {
        let address = host.split(separator: "%").first.map(String.init) ?? host
        if address == "::1" { return .loopback }
        if address.hasPrefix("fd7a:115c:a1e0:") { return .tailscale }
        let first = address.split(separator: ":", omittingEmptySubsequences: false).first.map(String.init) ?? ""
        guard let value = Int(first, radix: 16) else { return .publicInternet }
        if value & 0xFE00 == 0xFC00 { return .privateNetwork }  // fc00::/7 unique local
        if value & 0xFFC0 == 0xFE80 { return .privateNetwork }  // fe80::/10 link local
        return .publicInternet
    }
}
