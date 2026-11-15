import Foundation

/// Other addresses worth trying when the typed one does not answer as Hermes.
///
/// People type a bare host or IP ("192.168.1.20", "box.tailnet.ts.net") and forget that the Hermes dashboard listens
/// on port 9119. This extends the adapted-address mechanism (``ServerProbe/adaptedEndpoint``): the form probes the
/// typed address first, then these, and uses the first that answers as Hermes. Plain HTTP is only tried where
/// ``ConnectionAddress`` allows it, so a public host never gets an `http://` candidate.
public enum AddressAlternatives {
    /// The port the Hermes dashboard listens on by default.
    public static let dashboardPort = 9119

    /// The addresses to try after `endpoint`, in order. Empty when the user named a port, which is taken as typed.
    ///
    /// `input` is the text the user typed, which says whether they chose a scheme. Without one, a Tailscale
    /// `*.ts.net` name was tried over HTTPS, so HTTP on port 9119 and then on the default port follow.
    public static func candidates(for endpoint: HermesEndpoint, typed input: String) -> [HermesEndpoint] {
        guard let components = URLComponents(url: endpoint.baseURL, resolvingAgainstBaseURL: false),
            let host = components.host, components.port == nil
        else { return [] }
        let hadScheme = input.contains("://")
        let isHTTP = components.scheme?.lowercased() == "http"
        let httpAllowed = ConnectionAddress.classify(host: host) != .publicInternet
        let tries: [(scheme: String, port: Int?)]
        if isHTTP && !httpAllowed {
            // Plain HTTP to a public host is refused before any probe. Offer nothing, so no caller can try it.
            return []
        } else if isHTTP {
            tries = [("http", dashboardPort)]
        } else if httpAllowed && !hadScheme {
            tries = [("http", dashboardPort), ("http", nil)]
        } else {
            tries = [("https", dashboardPort)]
        }
        return tries.compactMap { scheme, port in
            var changed = components
            changed.scheme = scheme
            changed.port = port
            guard let url = changed.url, let candidate = HermesEndpoint(baseURL: url, headers: endpoint.headers),
                candidate != endpoint
            else { return nil }
            return candidate
        }
    }

    /// Probes `endpoint`, then each alternative while nothing answers as Hermes. The first alternative that answers is
    /// returned with ``ServerProbe/adaptedEndpoint`` set to it, unless the probe already adapted to an IP address.
    /// Only an unreachable or not-Hermes answer starts the search; a refusal, rate limit or sign-in answer comes from
    /// a server that is there, so it is thrown as it is. Rethrows the first failure when no alternative answers.
    public static func probe(
        _ endpoint: HermesEndpoint, typed input: String,
        using probe: (HermesEndpoint) async throws -> ServerProbe
    ) async throws -> ServerProbe {
        do {
            return try await probe(endpoint)
        } catch {
            let failure = (error as? ConnectionTestFailure) ?? GatewayConnectionTester.reachFailure(error)
            switch failure {
            case .unreachable, .notHermes: break
            default: throw error
            }
            for candidate in candidates(for: endpoint, typed: input) {
                guard !Task.isCancelled else { break }
                if var found = try? await probe(candidate) {
                    found.adaptedEndpoint = found.adaptedEndpoint ?? candidate
                    return found
                }
            }
            throw error
        }
    }
}
