import Foundation
import Testing

@testable import HermesSSH

@Suite struct SSHKeysTests {
    @Test func generatedKeyRoundTripsThroughOpenSSHFormat() throws {
        let key = SSHKeys.generateEd25519()
        let file = SSHKeys.openSSHPrivateKey(for: key, comment: "test")
        #expect(file.hasPrefix("-----BEGIN OPENSSH PRIVATE KEY-----"))
        guard case .ed25519(let imported) = try SSHKeys.importOpenSSHPrivateKey(file) else {
            Issue.record("expected an Ed25519 key")
            return
        }
        #expect(imported.rawRepresentation == key.rawRepresentation)
        let restored = try SSHKeys.ed25519(rawRepresentation: SSHKeys.rawRepresentation(of: key))
        #expect(restored.publicKey.rawRepresentation == key.publicKey.rawRepresentation)
    }

    @Test func authorizedKeysLineMatchesOpenSSH() throws {
        let key = SSHKeys.generateEd25519()
        let line = SSHKeys.authorizedKeysLine(for: key, comment: "phone")
        let parts = line.split(separator: " ")
        #expect(parts.count == 3 && parts[0] == "ssh-ed25519" && parts[2] == "phone")
        // Wire format: string "ssh-ed25519" + string <32-byte key>.
        let blob = try #require(Data(base64Encoded: String(parts[1])))
        #expect(blob.count == 4 + 11 + 4 + 32)
        #expect(blob.suffix(32) == key.publicKey.rawRepresentation)
    }

    @Test func rejectsNonOpenSSHKeys() {
        #expect(throws: SSHTunnelError.self) {
            try SSHKeys.importOpenSSHPrivateKey("-----BEGIN RSA PRIVATE KEY-----\nAAAA\n-----END RSA PRIVATE KEY-----")
        }
    }

    @Test func fingerprintMatchesSSHKeygen() throws {
        // `ssh-keygen -lf` prints SHA256:<unpadded base64 of sha256(blob)>.
        let info = try HostKeyInfo(
            openSSHKey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl test")
        #expect(info.openSSHKey == "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl")
        #expect(info.fingerprint == "SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU")
    }
}
