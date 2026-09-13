import XCTest
@testable import MagicPadCore

final class ProtocolLimitsTests: XCTestCase {
    func testCaps() {
        XCTAssertEqual(ProtocolLimits.maxFrameBytes, 1_048_576)
        XCTAssertEqual(ProtocolLimits.maxHeaderBytes, 16_384)
        XCTAssertEqual(ProtocolLimits.maxTypeChars, 2_000)
        XCTAssertEqual(ProtocolLimits.maxVoiceChars, 20_000)
        XCTAssertEqual(ProtocolLimits.proto, 1)
        XCTAssertEqual(ProtocolLimits.requiredWebSocketVersion, "13")
        XCTAssertEqual(ProtocolLimits.allowedOpcodes, [0x1, 0x2, 0x8, 0x9, 0xA])
    }
}
