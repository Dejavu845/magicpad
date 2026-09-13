import XCTest
@testable import MagicPadCore

final class CORSPolicyTests: XCTestCase {
    let lan = ["10.8.0.2"] // example-ip

    func testMissingAndEmptyStar() {
        let missing = CORSPolicy.accessControl(origin: nil, lanIPs: lan)
        XCTAssertEqual(missing?.allowOrigin, "*")
        XCTAssertEqual(missing?.needsVary, false)
        let empty = CORSPolicy.accessControl(origin: "", lanIPs: lan)
        XCTAssertEqual(empty?.allowOrigin, "*")
        XCTAssertEqual(empty?.needsVary, false)
        let blank = CORSPolicy.accessControl(origin: "  ", lanIPs: lan)
        XCTAssertEqual(blank?.allowOrigin, "*")
        XCTAssertEqual(blank?.needsVary, false)
    }

    func testEchoAllowlisted() {
        let loop = CORSPolicy.accessControl(origin: "http://127.0.0.1:7878", lanIPs: lan)
        XCTAssertEqual(loop?.allowOrigin, "http://127.0.0.1:7878")
        XCTAssertEqual(loop?.needsVary, true)
        let lanHit = CORSPolicy.accessControl(origin: "http://10.8.0.2:7878", lanIPs: lan) // example-ip
        XCTAssertEqual(lanHit?.allowOrigin, "http://10.8.0.2:7878") // example-ip
        XCTAssertEqual(lanHit?.needsVary, true)
    }

    func testOmitDisallowed() {
        XCTAssertNil(CORSPolicy.accessControl(origin: "http://evil.example", lanIPs: lan))
        XCTAssertNil(CORSPolicy.accessControl(origin: "null", lanIPs: lan))
        XCTAssertNil(CORSPolicy.accessControl(origin: "http://127.0.0.1/evil", lanIPs: lan))
    }
}
