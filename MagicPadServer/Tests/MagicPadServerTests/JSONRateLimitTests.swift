import XCTest
@testable import MagicPadCore

final class JSONRateLimitTests: XCTestCase {
    func testMetersTypeVoiceNotKeyOrPing() {
        let bucket = JSONRateLimit(tokensPerSec: 10, burst: 2)
        XCTAssertTrue(bucket.allow("key", now: 0))
        XCTAssertTrue(bucket.allow("ping", now: 0))
        XCTAssertTrue(bucket.allow("hello", now: 0))
        XCTAssertTrue(bucket.allow("type", now: 1))
        XCTAssertTrue(bucket.allow("voice", now: 1))
        XCTAssertFalse(bucket.allow("text", now: 1))
        XCTAssertTrue(bucket.allow("type", now: 1.2))
    }

    func testBurstAndRefillMatchLimits() {
        XCTAssertEqual(ProtocolLimits.maxClients, 8)
        XCTAssertEqual(ProtocolLimits.jsonTokensPerSec, 40)
        XCTAssertEqual(ProtocolLimits.jsonBurst, 80)
        XCTAssertEqual(JSONRateLimit.meteredTypes, ["type", "text", "voice"])
    }
}
