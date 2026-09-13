import XCTest
@testable import MagicPadCore

final class ProtocolLimitsTests: XCTestCase {
    func testCapsMatchKeyProtocolAndNewFloors() {
        XCTAssertEqual(ProtocolLimits.maxFrameBytes, 1_048_576)
        XCTAssertEqual(ProtocolLimits.maxHeaderBytes, 16_384)
        XCTAssertEqual(ProtocolLimits.maxTypeChars, KeyProtocol.maxTypeChars)
        XCTAssertEqual(ProtocolLimits.maxVoiceChars, KeyProtocol.maxVoiceChars)
        XCTAssertEqual(ProtocolLimits.proto, 1)
        XCTAssertEqual(ProtocolLimits.requiredWebSocketVersion, "13")
        XCTAssertEqual(ProtocolLimits.allowedOpcodes, [0x0, 0x1, 0x2, 0x8, 0x9, 0xA])
        XCTAssertEqual(ProtocolLimits.closeMessageTooBig, 1009)
        XCTAssertEqual(ProtocolLimits.closeUnsupportedData, 1003)
        XCTAssertEqual(ProtocolLimits.maxClients, 8)
        XCTAssertEqual(ProtocolLimits.jsonTokensPerSec, 40)
        XCTAssertEqual(ProtocolLimits.jsonBurst, 80)
    }
}
