import Foundation
import HermesKit
import Testing

@testable import HermesSSH

@Suite struct SSHKeyMaterialTests {
    @Test func generatedKeyRoundTripsThroughStorage() throws {
        let (stored, line) = SSHKeyMaterial.generate()
        #expect(line.hasPrefix("ssh-ed25519 AAAA"))
        #expect(line.hasSuffix(" simplyHermes"))
        #expect(SSHKeyMaterial.publicLine(for: stored) == line)
        let store = InMemoryCredentialStore()
        let id = UUID()
        try store.setSSHKey(stored, connection: id)
        #expect(try store.sshKey(connection: id) == stored)
        let file = try #require(SSHKeyMaterial.privateKeyFile(for: stored))
        let imported = try SSHKeyMaterial.importKey(file, passphrase: "")
        #expect(SSHKeyMaterial.publicLine(for: imported) == line)
    }

    @Test func importRejectsJunk() {
        #expect(throws: SSHTunnelError.self) { _ = try SSHKeyMaterial.importKey("not a key", passphrase: nil) }
    }

    @Test func configurationNeedsASecretAndPinsWhenKnown() throws {
        var settings = SSHSettings(host: " box.lan ", port: 2222, username: "jt")
        #expect(throws: ConnectionTestFailure.missingSecret) {
            _ = try SSHConnectionTester.configuration(settings, secrets: ConnectionSecrets()) { _ in true }
        }
        let key = SSHKeyMaterial.generate().key
        settings.pinnedHostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl"
        let secrets = ConnectionSecrets(sshKey: key)
        let configuration = try SSHConnectionTester.configuration(settings, secrets: secrets) { _ in true }
        #expect(configuration.host == "box.lan")
        #expect(configuration.port == 2222)
        if case .pinned = configuration.hostKey {} else { Issue.record("expected a pinned host key") }
        settings.authentication = .password
        #expect(throws: ConnectionTestFailure.missingSecret) {
            _ = try SSHConnectionTester.configuration(settings, secrets: ConnectionSecrets(sshPassword: "")) { _ in true
            }
        }
    }

    @Test func mapsTunnelErrors() {
        #expect(
            SSHConnectionTester.failure(SSHTunnelError.hostKeyMismatch(expected: "a", actual: "b"))
                == .hostKeyChanged(expected: "a", actual: "b"))
        #expect(SSHConnectionTester.failure(SSHTunnelError.hostKeyRejected(fingerprint: "x")) == .hostKeyRejected)
        guard case .ssh = SSHConnectionTester.failure(SSHTunnelError.hermesNotFound) else {
            Issue.record("hermesNotFound should be an SSH message")
            return
        }
    }
}
