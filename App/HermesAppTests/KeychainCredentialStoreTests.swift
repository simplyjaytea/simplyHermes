import Foundation
import Testing

@testable import HermesKit

#if canImport(Security)
    /// The real Keychain, on the simulator. If a saved password could not be read back, this fails with the OSStatus
    /// and names the cause. An unsigned test host cannot use the Keychain at all, so there the test checks nothing.
    /// Kept in its own file so it can be dropped without touching the others.
    struct KeychainCredentialStoreTests {
        /// `errSecMissingEntitlement`.
        private static let missingEntitlement: OSStatus = -34018

        @Test func aPasswordIsSavedReadBackAndRemovedThroughTheRealKeychain() throws {
            let store = KeychainCredentialStore(service: "com.simplyjaytea.simplyhermes.tests.\(UUID().uuidString)")
            let connection = UUID()
            defer { try? store.removeAll(connection: connection) }

            do {
                try store.setString("testbed-password", for: .gatewayPassword, connection: connection)
            } catch CredentialStoreError.keychain(status: Self.missingEntitlement) {
                // CI builds the test host with `CODE_SIGNING_ALLOWED=NO`, so it has no keychain access group and
                // every Keychain call answers -34018 (run 43593302488). That is the build, not the store: there is
                // nothing to check here. A signed host runs the rest.
                return
            }
            #expect(try store.string(for: .gatewayPassword, connection: connection) == "testbed-password")

            try store.setString("changed", for: .gatewayPassword, connection: connection)
            #expect(try store.string(for: .gatewayPassword, connection: connection) == "changed")

            try store.remove(.gatewayPassword, connection: connection)
            #expect(try store.string(for: .gatewayPassword, connection: connection) == nil)
        }
    }
#endif
