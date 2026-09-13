import XCTest
@testable import MagicPadCore

final class Cycle26BinaryFrameTests: XCTestCase {
    func testTooShortIsNil() {
        XCTAssertNil(BinaryFrame.parse(Data()))
        XCTAssertNil(BinaryFrame.parse(Data([0, 1, 2, 3, 4, 5])))
        XCTAssertEqual(BinaryFrame.minBytes, 7)
    }

    func testPointerFrame13() {
        var buf = [UInt8](repeating: 0, count: 13)
        buf[0] = 0
        buf[1] = 0x0A
        buf[2] = 0x00
        buf[3] = 0xF6
        buf[4] = 0xFF
        buf[6] = 0x01
        let frame = BinaryFrame.parse(Data(buf))
        XCTAssertNotNil(frame)
        XCTAssertEqual(frame?.phase, 0)
        XCTAssertEqual(frame?.dx, 10)
        XCTAssertEqual(frame?.dy, -10)
        XCTAssertEqual(frame?.buttons, 1)
        XCTAssertEqual(frame?.kind, "down")
        XCTAssertFalse(frame?.isGesture ?? true)
    }

    func testGestureFrame18() {
        var buf = [UInt8](repeating: 0, count: 18)
        buf[0] = 21
        buf[13] = 2
        buf[14] = 1
        buf[15] = 0xE8
        buf[16] = 0x03
        let frame = BinaryFrame.parse(Data(buf))
        XCTAssertEqual(frame?.kind, "pinch")
        XCTAssertEqual(frame?.fingers, 2)
        XCTAssertEqual(frame?.gesture, 1)
        XCTAssertEqual(frame?.ext, 1000)
        XCTAssertTrue(frame?.isGesture ?? false)
    }

    func testUnknownPhaseStaysUnknown() {
        let buf = [UInt8](repeating: 0, count: 7)
        var data = Data(buf)
        data[0] = 99
        XCTAssertEqual(BinaryFrame.parse(data)?.kind, "unknown")
    }
}
