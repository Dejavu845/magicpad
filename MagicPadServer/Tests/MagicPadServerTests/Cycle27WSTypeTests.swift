import XCTest
@testable import MagicPadCore

final class Cycle27WSTypeTests: XCTestCase {
    func testAllowlist() {
        XCTAssertEqual(WSType.parse("hello"), .hello)
        XCTAssertEqual(WSType.parse(" ping "), .ping)
        XCTAssertEqual(WSType.parse("classify"), .classify)
        XCTAssertEqual(WSType.parse("type"), .type)
        XCTAssertEqual(WSType.parse("text"), .text)
        XCTAssertEqual(WSType.parse("stt"), .stt)
        XCTAssertEqual(WSType.parse("key"), .key)
        XCTAssertEqual(WSType.parse("voice"), .voice)
    }

    func testUnknownOrWrongCaseIsNil() {
        XCTAssertNil(WSType.parse(nil))
        XCTAssertNil(WSType.parse(""))
        XCTAssertNil(WSType.parse("Hello"))
        XCTAssertNil(WSType.parse("drop"))
        XCTAssertNil(WSType.parse("upload"))
        XCTAssertNil(WSType.parse("pair"))
        XCTAssertFalse(WSType.inbound.contains("drop"))
    }
}
