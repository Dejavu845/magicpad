import XCTest
@testable import MagicPadCore

final class Cycle24STTLangTests: XCTestCase {
    func testAllowedPassThrough() {
        XCTAssertEqual(STTLang.parse("zh-CN"), "zh-CN")
        XCTAssertEqual(STTLang.parse("en-US"), "en-US")
        XCTAssertEqual(STTLang.parse("ja-JP"), "ja-JP")
    }

    func testUnknownFallsBackToZhCN() {
        XCTAssertEqual(STTLang.parse(nil), "zh-CN")
        XCTAssertEqual(STTLang.parse(""), "zh-CN")
        XCTAssertEqual(STTLang.parse("zh"), "zh-CN")
        XCTAssertEqual(STTLang.parse("en-us"), "zh-CN")
        XCTAssertEqual(STTLang.parse("fr-FR"), "zh-CN")
    }
}
