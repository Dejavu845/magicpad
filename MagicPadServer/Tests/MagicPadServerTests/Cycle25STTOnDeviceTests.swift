import XCTest
@testable import MagicPadCore

final class Cycle25STTOnDeviceTests: XCTestCase {
    func testJSONBoolPassThrough() {
        XCTAssertTrue(STTOnDevice.parse(true))
        XCTAssertFalse(STTOnDevice.parse(false))
    }

    func testMissingOrNonBoolDefaultsOn() {
        XCTAssertTrue(STTOnDevice.parse(nil))
        XCTAssertTrue(STTOnDevice.parse("true"))
        XCTAssertTrue(STTOnDevice.parse(1))
        XCTAssertTrue(STTOnDevice.parse(0))
    }
}
