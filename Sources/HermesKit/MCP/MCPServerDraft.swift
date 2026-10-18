import Foundation

/// How the app reaches a new MCP server.
public enum MCPTransport: Sendable, Equatable, CaseIterable {
    /// A program the server starts (stdio). Takes a command, arguments and variables.
    case command
    /// An address the server connects to (HTTP). Takes a URL and an authentication choice.
    case url
}

/// How a new URL server signs in.
public enum MCPAuthChoice: Sendable, Equatable, CaseIterable {
    /// No authentication.
    case none
    /// A bearer token, sent in the Authorization header.
    case bearerToken
    /// OAuth. The sign-in starts from the server's row after the server is added.
    case oauth
}

/// One environment variable of a new stdio server. The value can be a secret.
public struct MCPEnvPair: Sendable, Equatable, Identifiable {
    /// Identity for the form rows.
    public var id = UUID()
    /// Variable name.
    public var key: String
    /// Variable value.
    public var value: String

    /// Creates a row. Both fields start empty.
    public init(key: String = "", value: String = "") {
        self.key = key
        self.value = value
    }
}

/// A problem that stops a new server from being built. ``message`` is for the user.
public enum MCPDraftProblem: Error, Sendable, Equatable {
    /// The server has no name.
    case nameRequired
    /// A stdio server has no command.
    case commandRequired
    /// An HTTP server has no URL.
    case urlRequired
    /// A bearer-token server has no token.
    case tokenRequired
    /// A variable has a value but no name.
    case variableNameRequired
    /// Two variables share a name.
    case duplicateVariable(String)

    /// The sentence the form shows.
    public var message: String {
        switch self {
        case .nameRequired: "Give the server a name."
        case .commandRequired: "Enter the command that starts the server."
        case .urlRequired: "Enter the server's address."
        case .tokenRequired: "Enter the bearer token."
        case .variableNameRequired: "Every variable needs a name."
        case .duplicateVariable(let name): "“\(name)” is listed more than once."
        }
    }
}

/// What the add-server form holds. ``request()`` checks it and builds the `POST /api/mcp/servers` body.
public struct MCPServerDraft: Sendable, Equatable {
    /// Server name.
    public var name = ""
    /// Stdio or HTTP.
    public var transport = MCPTransport.command
    /// Program to start, for a stdio server.
    public var command = ""
    /// Arguments, one per line.
    public var argumentsText = ""
    /// Variables, for a stdio server. Blank rows are ignored.
    public var env: [MCPEnvPair] = []
    /// Address, for an HTTP server.
    public var url = ""
    /// Authentication, for an HTTP server.
    public var auth = MCPAuthChoice.none
    /// Bearer token, for an HTTP server with ``MCPAuthChoice/bearerToken``.
    public var bearerToken = ""

    /// Creates an empty draft.
    public init() {}

    /// The body for `POST /api/mcp/servers`, or the first problem. Fields of the other transport are left out.
    public func request() throws(MCPDraftProblem) -> MCPServerCreate {
        let serverName = Self.cleaned(name)
        guard !serverName.isEmpty else { throw .nameRequired }
        switch transport {
        case .command:
            let program = Self.cleaned(command)
            guard !program.isEmpty else { throw .commandRequired }
            let arguments = argumentsText.components(separatedBy: .newlines).map(Self.cleaned).filter { !$0.isEmpty }
            return MCPServerCreate(name: serverName, command: program, args: arguments, env: try variables())
        case .url:
            let address = Self.cleaned(url)
            guard !address.isEmpty else { throw .urlRequired }
            switch auth {
            case .none:
                return MCPServerCreate(name: serverName, url: address)
            case .oauth:
                return MCPServerCreate(name: serverName, url: address, auth: "oauth")
            case .bearerToken:
                let token = Self.cleaned(bearerToken)
                guard !token.isEmpty else { throw .tokenRequired }
                return MCPServerCreate(name: serverName, url: address, auth: "header", bearerToken: token)
            }
        }
    }

    /// The variables as a dictionary. Rows with neither name nor value are skipped.
    private func variables() throws(MCPDraftProblem) -> [String: String] {
        var result: [String: String] = [:]
        for pair in env {
            let key = Self.cleaned(pair.key)
            if key.isEmpty {
                guard pair.value.isEmpty else { throw .variableNameRequired }
                continue
            }
            guard result[key] == nil else { throw .duplicateVariable(key) }
            result[key] = pair.value
        }
        return result
    }

    private static func cleaned(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
