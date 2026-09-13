import XCTest
@testable import MagicPadCore

final class Cycle23STTActionTests: XCTestCase {
    func testStartStopStatusAliases() {
        XCTAssertEqual(STTAction.parse("start"), .start)
        XCTAssertEqual(STTAction.parse("BEGIN"), .start)
        XCTAssertEqual(STTAction.parse(" on "), .start)
        XCTAssertEqual(STTAction.parse("stop"), .stop)
        XCTAssertEqual(STTAction.parse("end"), .stop)
        XCTAssertEqual(STTAction.parse("OFF"), .stop)
        XCTAssertEqual(STTAction.parse("status"), .status)
    }

    func testUnknownIsNil() {
        XCTAssertNil(STTAction.parse(nil))
        XCTAssertNil(STTAction.parse(""))
        XCTAssertNil(STTAction.parse("listen"))
        XCTAssertNil(STTAction.parse("pair"))
    }
}
