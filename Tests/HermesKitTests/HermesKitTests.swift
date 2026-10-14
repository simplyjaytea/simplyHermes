import Testing

@testable import HermesKit

@Test func minimumServerVersionIsSet() {
    #expect(!HermesKit.minimumServerVersion.isEmpty)
}
