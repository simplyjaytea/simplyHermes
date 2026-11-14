import Foundation
import Testing

@testable import HermesKit

#if canImport(Security)
    /// The real Keychain, on the simulator, in a test host that is built with `CODE_SIGNING_ALLOWED=NO`. If a saved
    /// password could not be read back there, this fails with the OSStatus and names the cause. Kept in its own file so
    /// it can be dropped without touching the others.
    struct KeychainCredentialStoreTests {
        @Test func aPasswordIsSavedReadBackAndRemovedThroughTheRealKeychain() throws {
            let store = KeychainCredentialStore(service: "com.simplyjaytea.simplyhermes.tests.\(UUID().uuidString)")
            let connection = UUID()
            defer { try? store.removeAll(connection: connection) }

            try store.setString("testbed-password", for: .gatewayPassword, connection: connection)
            #expect(try store.string(for: .gatewayPassword, connection: connection) == "testbed-password")

            try store.setString("changed", for: .gatewayPassword, connection: connection)
            #expect(try store.string(for: .gatewayPassword, connection: connection) == "changed")

            try store.remove(.gatewayPassword, connection: connection)
            #expect(try store.string(for: .gatewayPassword, connection: connection) == nil)
        }
    }
#endif
