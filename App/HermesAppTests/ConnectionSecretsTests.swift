import Foundation
import HermesKit
import Testing

@testable import HermesUI

/// Why a saved testbed server ended in "Sign in again" in the UI tests (run 43495829201, #155): a gateway password is
/// kept only when the user turns on "Remember password". Without it nothing is stored, so connecting the saved server
/// finds no password (`missingSecret`) and the connection lands in `.signInRequired`.
@MainActor
struct ConnectionSecretsTests {
    private let endpoint = HermesEndpoint(string: "http://127.0.0.1:9119")!

    private func connection(remembers: Bool) -> ServerConnection {
        ServerConnection(
            name: "Testbed",
            kind: .gateway(
                GatewaySettings(endpoint: endpoint, signIn: .password(username: "tester"), remembersPassword: remembers)
            ))
    }

    private func model(_ store: any CredentialStore) -> ConnectionsModel {
        ConnectionsModel(store: nil, services: ConnectionServices(credentials: store, unlocker: AlwaysUnlocked()))
    }

    // (a) A password connection saved with Remember on is read back through the credential store.
    @Test func aRememberedPasswordIsSavedAndReadBack() async throws {
        let store = InMemoryCredentialStore()
        let model = model(store)
        let saved = connection(remembers: true)

        try model.save(saved, secrets: ConnectionSecrets(password: "testbed-password"))

        #expect(store.count == 1)
        let secrets = await model.secrets(for: saved, reason: "test")
        #expect(secrets?.password == "testbed-password")
    }

    // The cause: without Remember the password is not stored, so a later connect has none.
    @Test func aPasswordThatIsNotRememberedIsNotKeptSoTheSavedServerCannotSignIn() async throws {
        let store = InMemoryCredentialStore()
        let model = model(store)
        let saved = connection(remembers: false)

        try model.save(saved, secrets: ConnectionSecrets(password: "testbed-password"))

        #expect(store.count == 0)
        let secrets = await model.secrets(for: saved, reason: "test")
        #expect(secrets?.password == nil)
    }

    // (b) A store that refuses a write makes the save fail with the reason. It never reports the connection as saved.
    @Test func aCredentialStoreThatRefusesTheWriteMakesSaveThrow() throws {
        let model = model(RefusingCredentialStore())
        let saved = connection(remembers: true)

        #expect(throws: ConnectionSaveError.self) {
            try model.save(saved, secrets: ConnectionSecrets(password: "testbed-password"))
        }
        #expect(model.connections.isEmpty, "A connection whose password could not be saved must not be listed as saved")
    }
}

/// A credential store whose every write fails, like a Keychain that refuses the app.
private struct RefusingCredentialStore: CredentialStore {
    func set(_ data: Data, for kind: CredentialKind, connection: UUID) throws {
        throw CredentialStoreError.keychain(status: -34018)
    }
    func data(for kind: CredentialKind, connection: UUID) throws -> Data? { nil }
    func remove(_ kind: CredentialKind, connection: UUID) throws {}
}
