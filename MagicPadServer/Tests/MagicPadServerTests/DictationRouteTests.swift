import XCTest
@testable import MagicPadCore

final class DictationRouteTests: XCTestCase {
    func testEmptyWhisperDoesNotFallBack() {
        XCTAssertFalse(DictationRoute.shouldFallbackToApple(ok: false, reason: "empty"))
        XCTAssertFalse(DictationRoute.shouldFallbackToApple(ok: false, reason: " Empty "))
        XCTAssertFalse(DictationRoute.shouldFallbackToApple(ok: false, reason: "EMPTY"))
    }

    func testSuccessfulWhisperDoesNotFallBack() {
        XCTAssertFalse(DictationRoute.shouldFallbackToApple(ok: true, reason: nil))
        XCTAssertFalse(DictationRoute.shouldFallbackToApple(ok: true, reason: "empty"))
    }

    func testRealWhisperMissFallsBack() {
        XCTAssertTrue(DictationRoute.shouldFallbackToApple(ok: false, reason: "whisper_fail"))
        XCTAssertTrue(DictationRoute.shouldFallbackToApple(ok: false, reason: "whisper_unavailable"))
        XCTAssertTrue(DictationRoute.shouldFallbackToApple(ok: false, reason: "whisper_load"))
        XCTAssertTrue(DictationRoute.shouldFallbackToApple(ok: false, reason: nil))
        XCTAssertTrue(DictationRoute.shouldFallbackToApple(ok: false, reason: ""))
    }

    func testReportedEngineIsWhisperOnlyForWhisper() {
        XCTAssertEqual(DictationRoute.reportedEngine("whisper"), "whisper")
        XCTAssertEqual(DictationRoute.reportedEngine(" Whisper "), "whisper")
        XCTAssertEqual(DictationRoute.reportedEngine("apple"), "apple")
        XCTAssertEqual(DictationRoute.reportedEngine("none"), "apple")
        XCTAssertEqual(DictationRoute.reportedEngine(nil), "apple")
        XCTAssertEqual(DictationRoute.reportedEngine(""), "apple")
    }
}
