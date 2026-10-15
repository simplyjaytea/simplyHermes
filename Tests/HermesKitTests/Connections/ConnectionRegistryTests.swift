import Foundation
import HermesKit
import Testing

/// WP-15 gate: registry rules (primary, Open on launch, names, dedupe) and compatibility.
@Suite struct ConnectionRegistryTests {
    private func gateway(_ url: String, name: String = "Home") -> ServerConnection {
        ServerConnection(name: name, kind: .gateway(GatewaySettings(endpoint: HermesEndpoint(string: url)!)))
    }

    private func ssh(_ host: String, port: Int = 22, user: String = "jt", profile: String? = nil) -> ServerConnection {
        ServerConnection(
            name: host, kind: .ssh(SSHSettings(host: host, port: port, username: user, remoteProfile: profile)))
    }

    @Test func dedupeKeys() {
        var saved = SavedConnections()
        saved.upsert(gateway("https://Hermes.Example.com/base/"))
        saved.upsert(ssh("Box.lan", profile: "ops"))
        // Gateways: scheme and host case, default port and trailing slash do not matter; the path does.
        #expect(saved.duplicate(of: gateway("https://hermes.example.com:443/base")) != nil)
        #expect(saved.duplicate(of: gateway("https://hermes.example.com/base2")) == nil)
        #expect(saved.duplicate(of: gateway("http://hermes.example.com/base")) == nil)
        // SSH: user@host:port plus the remote profile.
        #expect(saved.duplicate(of: ssh(" box.LAN ", profile: "ops")) != nil)
        #expect(saved.duplicate(of: ssh("box.lan", profile: nil)) == nil)
        #expect(saved.duplicate(of: ssh("box.lan", port: 2222, profile: "ops")) == nil)
        #expect(saved.duplicate(of: ssh("box.lan", user: "root", profile: "ops")) == nil)
    }

    @Test func namesAreUniqueIgnoringCaseAndAtMost64Characters() {
        var saved = SavedConnections()
        let home = gateway("https://one.example", name: "Home server")
        saved.upsert(home)
        let other = UUID()
        #expect(saved.nameProblem("  ", for: other) == .empty)
        #expect(saved.nameProblem(String(repeating: "a", count: 65), for: other) == .tooLong)
        #expect(saved.nameProblem(String(repeating: "a", count: 64), for: other) == nil)
        #expect(saved.nameProblem("HOME SERVER ", for: other) == .taken(name: "Home server"))
        #expect(saved.nameProblem("home server", for: home.id) == nil, "Renaming to its own name is fine")
        #expect(saved.uniqueName("home server", for: other) == "home server 2")
        #expect(saved.uniqueName("Office", for: other) == "Office")
    }

    @Test func primaryAndOpenOnLaunch() {
        var saved = SavedConnections()
        let one = gateway("https://one.example", name: "One")
        let two = gateway("https://two.example", name: "Two")
        let three = gateway("https://three.example", name: "Three")
        for connection in [one, two, three] { saved.upsert(connection) }
        #expect(saved.primary == one, "The first connection is primary")
        #expect(saved.launchConnection == one)

        saved.setPrimary(two.id)
        #expect(saved.launchConnection == two)

        saved.openOnLaunch = .lastUsed
        #expect(saved.launchConnection == two, "Nothing used yet: the primary opens")
        saved.markConnected(three.id)
        #expect(saved.launchConnection == three)

        saved.remove(id: three.id)
        #expect(saved.lastUsedID == nil)
        #expect(saved.launchConnection == two)
        saved.remove(id: two.id)
        #expect(saved.primary == one, "Deleting the primary promotes the first one left")
    }

    @Test func readsFilesFromBeforeTheRegistry() throws {
        let one = gateway("https://one.example", name: "One")
        let old = """
            {"connections":[\(String(bytes: try JSONEncoder().encode(one), encoding: .utf8) ?? "")],
             "activeID":"\(one.id.uuidString)"}
            """
        let saved = try JSONDecoder().decode(SavedConnections.self, from: Data(old.utf8))
        #expect(saved.primaryID == one.id)
        #expect(saved.openOnLaunch == .primary)
        #expect(saved.lastUsedID == nil)
        let again = try JSONDecoder().decode(SavedConnections.self, from: try JSONEncoder().encode(saved))
        #expect(again == saved)
    }
}

@Suite struct ServerCompatibilityTests {
    private func status(_ json: String) throws -> ServerStatus {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ServerStatus.self, from: Data(json.utf8))
    }

    @Test func checksReleaseDateAndConfigVersionNotVersion() throws {
        let pinned = try status(#"{"version":"unknown","release_date":"2026.9.24","latest_config_version":50}"#)
        #expect(ServerCompatibility.check(pinned) == .compatible)
        let newer = try status(#"{"version":"0.1.0","release_date":"2026.10.3","latest_config_version":52}"#)
        #expect(ServerCompatibility.check(newer) == .compatible, "version is ignored")
        let old = try status(#"{"version":"9.9.9","release_date":"2026.8.30"}"#)
        #expect(ServerCompatibility.check(old) == .updateRequired(found: "release 2026.8.30"))
        let oldConfig = try status(#"{"release_date":"2026.9.24","latest_config_version":41}"#)
        #expect(ServerCompatibility.check(oldConfig) == .updateRequired(found: "config version 41"))
        #expect(ServerCompatibility.check(try status("{}")) == .compatible, "Missing fields are not held against it")
        let odd = try status(#"{"release_date":"nightly"}"#)
        #expect(ServerCompatibility.check(odd) == .compatible)
    }

    @Test func checksDesktopContract() {
        #expect(ServerCompatibility.check(desktopContract: .int(8)) == .compatible)
        #expect(ServerCompatibility.check(desktopContract: .int(7)) == .updateRequired(found: "desktop contract 7"))
        #expect(ServerCompatibility.check(desktopContract: .string("9")) == .newerThanApp(contract: 9))
        #expect(ServerCompatibility.check(desktopContract: nil) == .compatible)
        #expect(!ServerCompatibility.updateRequired(found: "x").allowsConnecting)
        #expect(ServerCompatibility.newerThanApp(contract: 9).allowsConnecting)
    }
}
