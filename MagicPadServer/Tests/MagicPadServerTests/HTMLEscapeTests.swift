import XCTest
@testable import MagicPadCore

final class HTMLEscapeTests: XCTestCase {
    func testEscapesMarkup() {
        XCTAssertEqual(HTMLEscape.escape("<img src=x onerror=alert(1)>"),
                       "&lt;img src=x onerror=alert(1)&gt;")
        XCTAssertEqual(HTMLEscape.escape("a&b"), "a&amp;b")
        XCTAssertEqual(HTMLEscape.escape("\"x\""), "&quot;x&quot;")
        XCTAssertEqual(HTMLEscape.escape("'y'"), "&#39;y&#39;")
    }

    func testAmpersandFirst() {
        XCTAssertEqual(HTMLEscape.escape("<>&"), "&lt;&gt;&amp;")
    }
}
