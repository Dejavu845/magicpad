// OriginPolicyTests.swift — CSWSH allowlist (no AppKit). Vectors match scripts/test-protocol.py.

import XCTest
@testable import MagicPadCore

final class OriginPolicyTests: XCTestCase {
    let lan = ["10.8.0.2"] // example-ip

    func testNilAndEmptyAllowed() {
        XCTAssertTrue(OriginPolicy.isAllowed(origin: nil, lanIPs: lan))
        XCTAssertTrue(OriginPolicy.isAllowed(origin: "", lanIPs: lan))
        XCTAssertTrue(OriginPolicy.isAllowed(origin: "   ", lanIPs: lan))
    }

    func testLoopback() {
        XCTAssertTrue(OriginPolicy.isAllowed(origin: "http://127.0.0.1:7878", lanIPs: lan))
        XCTAssertTrue(OriginPolicy.isAllowed(origin: "https://localhost:7879", lanIPs: lan))
        XCTAssertTrue(OriginPolicy.isAllowed(origin: "http://[::1]:7878", lanIPs: lan))
        XCTAssertTrue(OriginPolicy.isAllowed(origin: "https://127.0.0.1:7878/", lanIPs: lan))
        XCTAssertTrue(OriginPolicy.isAllowed(origin: "ws://127.0.0.1:7878", lanIPs: lan))
        XCTAssertTrue(OriginPolicy.isAllowed(origin: "wss://localhost:7879", lanIPs: lan))
    }

    func testLanIPInList() {
        XCTAssertTrue(OriginPolicy.isAllowed(origin: "http://10.8.0.2:7878", lanIPs: lan)) // example-ip
    }

    func testLanIPNotInList() {
        XCTAssertFalse(OriginPolicy.isAllowed(origin: "http://10.8.0.99:7878", lanIPs: lan)) // example-ip
    }

    func testEvilAndNull() {
        XCTAssertFalse(OriginPolicy.isAllowed(origin: "http://evil.example", lanIPs: lan))
        XCTAssertFalse(OriginPolicy.isAllowed(origin: "null", lanIPs: lan))
        XCTAssertFalse(OriginPolicy.isAllowed(origin: "file://127.0.0.1", lanIPs: lan))
    }

    func testHostExtractor() {
        XCTAssertEqual(OriginPolicy.host(fromOrigin: "http://127.0.0.1:7878"), "127.0.0.1")
        XCTAssertNil(OriginPolicy.host(fromOrigin: nil))
        XCTAssertNil(OriginPolicy.host(fromOrigin: "null"))
    }
}
