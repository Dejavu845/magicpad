import XCTest
@testable import MagicPadCore

final class CORSPolicyTests: XCTestCase {
    let lan = ["10.8.0.2"] // example-ip

    func testMissingAndEmptyStar() {
        XCTAssertEqual(CORSPolicy.accessControlAllowOrigin(origin: nil, lanIPs: lan), "*")
        XCTAssertEqual(CORSPolicy.accessControlAllowOrigin(origin: "", lanIPs: lan), "*")
        XCTAssertEqual(CORSPolicy.accessControlAllowOrigin(origin: "  ", lanIPs: lan), "*")
    }

    func testEchoAllowlisted() {
        XCTAssertEqual(
            CORSPolicy.accessControlAllowOrigin(origin: "http://127.0.0.1:7878", lanIPs: lan),
            "http://127.0.0.1:7878"
        )
        XCTAssertEqual(
            CORSPolicy.accessControlAllowOrigin(origin: "http://10.8.0.2:7878", lanIPs: lan), // example-ip
            "http://10.8.0.2:7878" // example-ip
        )
    }

    func testOmitDisallowed() {
        XCTAssertNil(CORSPolicy.accessControlAllowOrigin(origin: "http://evil.example", lanIPs: lan))
        XCTAssertNil(CORSPolicy.accessControlAllowOrigin(origin: "null", lanIPs: lan))
        XCTAssertNil(CORSPolicy.accessControlAllowOrigin(origin: "http://127.0.0.1/evil", lanIPs: lan))
    }
}
