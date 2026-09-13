import XCTest
@testable import MagicPadCore

final class FilenamesTests: XCTestCase {
    func testStripsPathAndUnsafe() {
        XCTAssertEqual(Filenames.sanitize("../../etc/passwd"), "passwd")
        XCTAssertEqual(Filenames.sanitize("a<>b.txt"), "a__b.txt")
        XCTAssertEqual(Filenames.sanitize("."), Filenames.fallback)
        XCTAssertEqual(Filenames.sanitize(".."), Filenames.fallback)
        XCTAssertEqual(Filenames.sanitize("   "), Filenames.fallback)
        XCTAssertEqual(Filenames.sanitize("文件.txt"), "文件.txt")
        XCTAssertEqual(Filenames.sanitize("résumé.pdf"), "résumé.pdf")
        XCTAssertEqual(Filenames.sanitize("foo/"), "foo")
        XCTAssertEqual(Filenames.sanitize(#"..\..\etc\passwd"#), "passwd")
        XCTAssertEqual(Filenames.sanitize("..."), Filenames.fallback)
        XCTAssertEqual(Filenames.sanitize("é.txt"), "é.txt")
    }

    func testClampsLengthKeepsSuffix() {
        let long = String(repeating: "a", count: 200) + ".txt"
        let got = Filenames.sanitize(long)
        XCTAssertEqual(got.count, Filenames.maxLength)
        XCTAssertTrue(got.hasSuffix(".txt"))
    }
}
