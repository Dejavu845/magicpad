// OriginPolicyTests.swift — CSWSH allowlist (no AppKit).
// Table matches scripts/fixtures/origin-vectors.json + scripts/test-protocol.py.

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
        XCTAssertTrue(OriginPolicy.isAllowed(origin: "HTTP://LOCALHOST", lanIPs: lan))
    }

    func testLanIPInList() {
        XCTAssertTrue(OriginPolicy.isAllowed(origin: "http://10.8.0.2:7878", lanIPs: lan)) // example-ip
    }

    func testLanIPNotInList() {
        XCTAssertFalse(OriginPolicy.isAllowed(origin: "http://10.8.0.99:7878", lanIPs: lan)) // example-ip
    }

    func testEmptyLanDegradesToLoopback() {
        XCTAssertTrue(OriginPolicy.isAllowed(origin: "http://127.0.0.1:7878", lanIPs: []))
        XCTAssertFalse(OriginPolicy.isAllowed(origin: "http://10.8.0.2:7878", lanIPs: [])) // example-ip
    }

    func testEvilNullFileAndStructure() {
        XCTAssertFalse(OriginPolicy.isAllowed(origin: "http://evil.example", lanIPs: lan))
        XCTAssertFalse(OriginPolicy.isAllowed(origin: "null", lanIPs: lan))
        XCTAssertFalse(OriginPolicy.isAllowed(origin: "file://127.0.0.1", lanIPs: lan))
        XCTAssertFalse(OriginPolicy.isAllowed(origin: "http://127.0.0.1:7878/evil", lanIPs: lan))
        XCTAssertFalse(OriginPolicy.isAllowed(origin: "http://127.0.0.1?x=1", lanIPs: lan))
        XCTAssertFalse(OriginPolicy.isAllowed(origin: "http://127.0.0.1#f", lanIPs: lan))
        XCTAssertFalse(OriginPolicy.isAllowed(origin: "http://127.0.0.1@evil.example", lanIPs: lan))
        XCTAssertFalse(OriginPolicy.isAllowed(origin: "http://127.0.0.1.evil.example", lanIPs: lan))
        XCTAssertFalse(OriginPolicy.isAllowed(origin: "http://localhost.evil.example", lanIPs: lan))
        XCTAssertFalse(OriginPolicy.isAllowed(origin: "http://mymac.local:7878", lanIPs: lan))
        XCTAssertFalse(OriginPolicy.isAllowed(origin: "http://%31%32%37.0.0.1", lanIPs: lan))
        XCTAssertFalse(OriginPolicy.isAllowed(origin: "http://127.0.0.1:7878/#", lanIPs: lan))
        XCTAssertFalse(OriginPolicy.isAllowed(origin: "http://127.0.0.1:7878?", lanIPs: lan))
        XCTAssertFalse(OriginPolicy.isAllowed(origin: "http://@127.0.0.1:7878", lanIPs: lan))
        XCTAssertFalse(OriginPolicy.isAllowed(origin: "http://:@127.0.0.1:7878", lanIPs: lan))
    }

    func testHostExtractorUsesSameParse() {
        XCTAssertEqual(OriginPolicy.host(fromOrigin: "http://127.0.0.1:7878"), "127.0.0.1")
        XCTAssertNil(OriginPolicy.host(fromOrigin: nil))
        XCTAssertNil(OriginPolicy.host(fromOrigin: "null"))
        XCTAssertNil(OriginPolicy.host(fromOrigin: "file://127.0.0.1"))
        XCTAssertNil(OriginPolicy.host(fromOrigin: "http://127.0.0.1:7878/evil"))
    }
}
