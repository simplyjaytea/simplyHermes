import Foundation

// MARK: - Media

extension RESTClient {
    /// `GET /api/media`: the bytes of an image the server names by path. Paths outside the media roots answer 403.
    public func mediaFile(path: String) async throws -> Data {
        try await sendRaw("GET", "/api/media", query: [URLQueryItem(name: "path", value: path)]).body
    }

    /// `GET /api/media/proxy`: the bytes of a remote image, fetched through the server. Only allowed hosts work.
    public func proxiedMedia(url: String) async throws -> Data {
        try await sendRaw("GET", "/api/media/proxy", query: [URLQueryItem(name: "url", value: url)]).body
    }
}
