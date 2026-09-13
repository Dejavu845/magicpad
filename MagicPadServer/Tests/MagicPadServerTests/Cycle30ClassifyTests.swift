import XCTest
@testable import MagicPadCore

final class Cycle30ClassifyTests: XCTestCase {
    func testNeverInjects() {
        XCTAssertFalse(Classify.injects)
        XCTAssertEqual(Classify.jsonType, "classify")
        XCTAssertEqual(Classify.ackType, "classify_ack")
    }

    func testKindTrim() {
        XCTAssertEqual(Classify.parseKind(" pinch "), "pinch")
        XCTAssertNil(Classify.parseKind(nil))
        XCTAssertNil(Classify.parseKind("   "))
    }
}
