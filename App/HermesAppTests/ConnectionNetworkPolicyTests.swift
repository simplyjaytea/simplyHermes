import XCTest

final class ConnectionNetworkPolicyTests: XCTestCase {
    func testDeviceAppAllowsHTTPToPrivateAndTailscaleIPRanges() throws {
        let ats = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "NSAppTransportSecurity") as? [String: Any])
        let domains = try XCTUnwrap(ats["NSExceptionDomains"] as? [String: [String: Any]])
        for range in ["100.64.0.0/10", "fd7a:115c:a1e0::/48", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"] {
            XCTAssertEqual(domains[range]?["NSExceptionAllowsInsecureHTTPLoads"] as? Bool, true, range)
        }
        XCTAssertNotEqual(ats["NSAllowsArbitraryLoads"] as? Bool, true)
        XCTAssertEqual(domains["ts.net"]?["NSIncludesSubdomains"] as? Bool, true)
    }
}
