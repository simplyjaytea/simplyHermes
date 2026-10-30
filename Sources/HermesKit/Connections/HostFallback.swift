import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

/// Looks up the IP addresses of a host name.
public protocol HostResolving: Sendable {
    /// The addresses of `host` as numeric strings, IPv4 first. Empty when the name doesn't resolve.
    func addresses(of host: String) async -> [String]
}

/// Resolves names with the system resolver (`getaddrinfo`), which includes Tailscale's MagicDNS.
public struct SystemHostResolver: HostResolving {
    public init() {}

    public func addresses(of host: String) async -> [String] {
        await Task.detached { Self.lookup(host) }.value
    }

    private static func lookup(_ host: String) -> [String] {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        #if canImport(Darwin)
            hints.ai_socktype = SOCK_STREAM
        #else
            hints.ai_socktype = Int32(SOCK_STREAM.rawValue)
        #endif
        var list: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &list) == 0, let first = list else { return [] }
        defer { freeaddrinfo(first) }
        var v4: [String] = []
        var v6: [String] = []
        var next: UnsafeMutablePointer<addrinfo>? = first
        while let entry = next?.pointee {
            next = entry.ai_next
            guard let address = entry.ai_addr else { continue }
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard
                getnameinfo(
                    address, entry.ai_addrlen, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0
            else { continue }
            let text = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            if entry.ai_family == AF_INET {
                if !v4.contains(text) { v4.append(text) }
            } else if !v6.contains(text) {
                v6.append(text)
            }
        }
        return v4 + v6
    }
}

/// What the app tries when Hermes refuses the address name (`400 Invalid Host header`).
///
/// Hermes answers only to the address it is bound to and to `dashboard.public_url`. A server bound to its Tailscale
/// IP refuses the MagicDNS name, short or full, unless the operator set a public URL. Over plain HTTP the app can
/// reach the same server by its IP instead, so it adapts rather than asking the user to change Hermes. Over HTTPS
/// the certificate names the host, so an IP can't stand in and there is no fallback.
public enum HostFallback {
    /// The same endpoint with the host replaced by each address `endpoint`'s name resolves to. Empty for HTTPS and
    /// for a host that is already an IP address.
    public static func candidates(for endpoint: HermesEndpoint, resolver: any HostResolving) async -> [HermesEndpoint] {
        guard let components = URLComponents(url: endpoint.baseURL, resolvingAgainstBaseURL: false),
            components.scheme?.lowercased() == "http", let host = components.host, !isAddressLiteral(host)
        else { return [] }
        let addresses = await resolver.addresses(of: host)
        return addresses.compactMap { address in
            let literal = address.contains(":") ? "[\(address.split(separator: "%").first ?? "")]" : address
            let port = components.port.map { ":\($0)" } ?? ""
            return HermesEndpoint(
                string: "http://\(literal)\(port)\(components.percentEncodedPath)", headers: endpoint.headers)
        }
    }

    /// The note under the address when the app uses an IP address in place of the typed name.
    public static func note(typed: HermesEndpoint, adapted: HermesEndpoint) -> String {
        let name = typed.baseURL.host() ?? "this name"
        let address = adapted.baseURL.host() ?? "its IP address"
        return "Hermes doesn't answer to \(name), so the app connects to \(address), the same server."
    }

    /// True for an IPv4 or IPv6 literal, with or without brackets.
    static func isAddressLiteral(_ host: String) -> Bool {
        if host.contains(":") || host.hasPrefix("[") { return true }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { UInt8($0) != nil }
    }
}
