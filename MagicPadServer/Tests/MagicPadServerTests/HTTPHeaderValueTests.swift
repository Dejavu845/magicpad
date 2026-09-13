// HTTPHeaderValueTests.swift — empty Origin: must not become the header name (Opus M1).

import XCTest
@testable import MagicPadCore

final class HTTPHeaderValueTests: XCTestCase {
    func testMissingIsNil() {
        XCTAssertNil(HTTPHeaderValue.first("GET / HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n", name: "origin"))
    }

    func testPresentValue() {
        let blob = "GET / HTTP/1.1\r\nOrigin: http://evil.example\r\n\r\n"
        XCTAssertEqual(HTTPHeaderValue.first(blob, name: "origin"), "http://evil.example")
    }

    func testEmptyValueIsEmptyStringNotName() {
        // Today's WebSocketServer.headerValue returns "Origin" here (split drops empty).
        let blob = "GET / HTTP/1.1\r\nOrigin:\r\n\r\n"
        XCTAssertEqual(HTTPHeaderValue.first(blob, name: "origin"), "")
        XCTAssertTrue(OriginPolicy.isAllowed(origin: HTTPHeaderValue.first(blob, name: "origin"), lanIPs: []))
    }

    func testHTTPPostOriginDelegates() {
        XCTAssertTrue(HTTPPostOrigin.allows(nil, lanIPs: []))
        XCTAssertFalse(HTTPPostOrigin.allows("http://evil.example", lanIPs: []))
    }
}
