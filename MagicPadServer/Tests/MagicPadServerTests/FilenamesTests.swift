import XCTest
@testable import MagicPadCore

final class FilenamesTests: XCTestCase {
    func testStripsPathAndUnsafe() {
        XCTAssertEqual(Filenames.sanitize("../../etc/passwd"), "passwd")
        XCTAssertEqual(Filenames.sanitize("a<>b.txt"), "a__b.txt")
        XCTAssertEqual(Filenames.sanitize("."), Filenames.fallback)
        XCTAssertEqual(Filenames.sanitize(".."), Filenames.fallback)
        XCTAssertEqual(Filenames.sanitize("   "), Filenames.fallback)
    }

    func testClampsLength() {
        let long = String(repeating: "a", count: 200) + ".txt"
        XCTAssertEqual(Filenames.sanitize(long).count, Filenames.maxLength)
    }
}
